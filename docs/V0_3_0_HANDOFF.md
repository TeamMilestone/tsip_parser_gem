# tsip_parser gem v0.3.0 핸드오프 — `TsipParser::Message.parse` 네이티브 바인딩

작성일: 2026-04-19
대상 gem: `tsip_parser` v0.2.3 → v0.3.0
대상 crate: `tsip-parser` v0.3.0 (crates.io publish 완료, 2026-04-19)
연관 문서:
- `tsip_parser_gem/docs/V0_2_3_HANDOFF.md` — 직전 릴리스 (`Address.new` allocator)
- `sip_uri_crate/docs/V0_3_0_HANDOFF.md` — crate 측 설계 (Parser 네이티브화 결정)
- `tsip-core/docs/PERFORMANCE_HANDOVER.md` — 10차 세션 (bridge v0.2.3 integration)

## 1. 배경

tsip-core 10차 세션 결과 bridge ON cps **7,239** (목표 8,000~9,500 의 ~90%). Uri/Address 네이티브화 효과는 수확 완료. stackprof 기준 남은 pure-Ruby 핫패스는 `TsipCore::Sip::Parser.parse` 한 덩어리 (self 15~18%). v0.3.0 에서 메시지 파서를 네이티브화해서 이 덩어리를 제거한다.

crate 측은 v0.3.0 작업 완료:
- `src/message.rs` — `Message::parse(&[u8]) -> Result<Message, ParseError>`, `StartLine`, canonical header 테이블, §7.3.1 line folding, Content-Length 검증
- 테스트 48건 (정상 28 / malformed 20) 전부 통과
- fuzz 30초 smoke 4.78M runs panic=0
- bench INVITE 10-header **1.48 μs** (핸드오프 목표 5~8 μs 대비 3~5× 여유)
- crates.io 에 `tsip-parser = "0.3.0"` 으로 publish

## 2. 스코프

### In scope
- gem 에 `TsipParser::Message` 클래스 추가 + singleton method `parse(raw)` 노출
- Ruby 반환 계약: 단일 `Hash`. (`:kind`, `:method|status_code`, `:headers`, `:body`, ...)
- `ParseError` 매핑 — crate v0.3.0 의 신규 variant 8종 전부 동일 `TsipParser::ParseError` 로 raise
- Content-Length 검증 결과는 crate 가 ParseError 로 올리고 gem 은 그대로 전달

### Out of scope
- `TsipParser::Message.new` (0-arg allocator) — v0.3.0 에서는 필요 없음. tsip-core 가 `.parse` 로만 구성하고 `Message` 객체를 별도로 보유하지 않음 (Hash 로 풀어서 `TsipCore::Sip::Message.new` 에 주입).
- Via/CSeq/Contact 등 구조화 헤더 값 파싱 — crate 도 raw String 그대로 반환. gem 도 Hash 에 raw 값 그대로 담음.
- `Message#to_s` / re-render — crate `Message` 에도 Display impl 없음. 네트워크 측은 raw bytes 재사용.

## 3. Crate 의존성 갱신

### 3.1 `ext/tsip_parser/Cargo.toml`

```toml
[dependencies]
magnus = { version = "0.8" }
tsip-parser = "0.3"
```

`"0.2"` → `"0.3"`. crates.io 에서 이미 publish 됨. 로컬 dev 시 `path = "../../sip_uri_crate"` 추가 가능하나 릴리스 빌드에서는 path 제거.

## 4. Gem 측 변경

### 4.1 `ext/tsip_parser/src/message.rs` 신규

```rust
use magnus::{function, prelude::*, Error, RArray, RHash, RString, Ruby, Symbol};
use tsip_parser::{Message, StartLine};

pub fn init(ruby: &Ruby, parent: &magnus::RModule) -> Result<(), Error> {
    let class = parent.define_class("Message", ruby.class_object())?;
    class.define_singleton_method("parse", function!(parse, 1))?;
    Ok(())
}

fn parse(input: RString) -> Result<RHash, Error> {
    let ruby = unsafe { Ruby::get_unchecked() };
    let bytes = unsafe { input.as_slice() };
    let m = Message::parse(bytes).map_err(|e| crate::error::to_ruby(&ruby, e))?;

    let hash = ruby.hash_new_capa(6);
    match m.start_line {
        StartLine::Request { method, request_uri, sip_version } => {
            hash.aset(Symbol::new("kind"), Symbol::new("request"))?;
            hash.aset(Symbol::new("method"), method)?;
            hash.aset(Symbol::new("request_uri"), request_uri)?;
            hash.aset(Symbol::new("sip_version"), sip_version)?;
        }
        StartLine::Response { sip_version, status_code, reason_phrase } => {
            hash.aset(Symbol::new("kind"), Symbol::new("response"))?;
            hash.aset(Symbol::new("sip_version"), sip_version)?;
            hash.aset(Symbol::new("status_code"), status_code)?;
            hash.aset(Symbol::new("reason_phrase"), reason_phrase)?;
        }
    }

    hash.aset(Symbol::new("headers"), build_headers_hash(&ruby, &m.headers)?)?;

    // Body encoding — SIP body 는 임의 bytes. ASCII-8BIT 로 강제.
    let body = RString::from_slice(&m.body);
    // magnus 0.8 에서 RString::from_slice 는 UTF-8 플래그를 붙이지 않고 ASCII-8BIT.
    hash.aset(Symbol::new("body"), body)?;

    Ok(hash)
}

fn build_headers_hash(ruby: &Ruby, pairs: &[(String, String)]) -> Result<RHash, Error> {
    let hash = ruby.hash_new_capa(pairs.len().min(16));
    for (name, value) in pairs {
        let key = RString::new(name);
        let arr: RArray = match hash.aref(key) {
            Ok(existing) => existing,
            Err(_) => {
                let new_arr = ruby.ary_new_capa(1);
                hash.aset(RString::new(name), new_arr)?;
                hash.aref(RString::new(name))?
            }
        };
        arr.push(value.as_str())?;
    }
    Ok(hash)
}
```

**주의**: magnus `RString::from_slice(&[u8])` 의 encoding 결과는 magnus 버전에 따라 다를 수 있음. 실제 `rake compile` 후 Ruby irb 에서 `TsipParser::Message.parse(raw)[:body].encoding` 확인 필요. UTF-8 로 잡히면 `ruby.enc_associate_index(body, rb_ascii8bit_encindex())` 또는 Ruby facade 에서 `body.force_encoding(Encoding::ASCII_8BIT)` 처리.

### 4.2 `ext/tsip_parser/src/lib.rs` 등록

```rust
mod address;
mod error;
mod message;  // ← 추가
mod uri;

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("TsipParser")?;
    uri::init(ruby, &module)?;
    address::init(ruby, &module)?;
    message::init(ruby, &module)?;  // ← 추가
    Ok(())
}
```

### 4.3 에러 매핑 확인 — `ext/tsip_parser/src/error.rs`

현재 `to_ruby` 는 `tsip_parser::ParseError::to_string()` 결과를 message 로 `TsipParser::ParseError` 를 raise. crate v0.3.0 에서 추가된 8종 variant (MessageTooLarge, EmptyMessage, InvalidStartLine, InvalidStatusCode, HeaderMissingColon, NegativeContentLength, OversizeContentLength, BadContentLength) 는 모두 `Display` 구현이 있어 `to_string()` 이 동작. **gem 측 `error.rs` 는 변경 불필요**.

tsip-core bridge 가 variant 별로 분기할 일이 있다면 message 문자열 파싱 대신 enum 을 노출하는 쪽이 맞지만, 현 용례는 `rescue TsipParser::ParseError` 한 줄이라 불필요.

### 4.4 Ruby facade — `lib/tsip_parser/message.rb` (선택)

crate v0.3.0 의 `Message::parse` 는 Hash 반환이라 facade class 는 필수 아님. 다만 body encoding 보정을 한 곳에서 하려면 다음 정도:

```ruby
# lib/tsip_parser/message.rb (선택, 최소)
module TsipParser
  class Message
    class << self
      alias_method :_raw_parse, :parse unless method_defined?(:_raw_parse)

      def parse(raw)
        h = _raw_parse(raw)
        body = h[:body]
        if body && body.encoding != Encoding::ASCII_8BIT
          h[:body] = body.b
        end
        h
      end
    end
  end
end
```

body encoding 이 magnus 단에서 이미 ASCII-8BIT 로 나온다면 facade 생략 가능. **smoke test 결과에 따라 결정**.

`lib/tsip_parser.rb` 에는 `require_relative "tsip_parser/message"` 를 `address` 뒤에 한 줄 추가.

### 4.5 Ruby 상 계약

```ruby
TsipParser::Message.parse("INVITE sip:bob@biloxi.example.com SIP/2.0\r\n...\r\n\r\n")
# => {
#   kind: :request,
#   method: "INVITE",
#   request_uri: "sip:bob@biloxi.example.com",
#   sip_version: "SIP/2.0",
#   headers: {
#     "Via" => ["SIP/2.0/UDP ..."],
#     "From" => ["Alice <sip:alice@...>;tag=..."],
#     ...
#   },
#   body: ""  # ASCII-8BIT
# }

TsipParser::Message.parse("SIP/2.0 404 Not Found\r\n...\r\n\r\n")
# => {
#   kind: :response,
#   sip_version: "SIP/2.0",
#   status_code: 404,
#   reason_phrase: "Not Found",
#   headers: { ... },
#   body: ""
# }
```

주의:
- `headers` 의 key 는 **canonical name String** (예: `"Via"`, `"Call-ID"`, `"Content-Length"`).
- value 는 **Array<String>** — 같은 이름 헤더가 여러 번 등장해도 원 순서 보존 (RFC 3261 Via 다중 라우팅 의존).
- method 는 항상 대문자 정규화 (`"INVITE"`, `"REGISTER"`, ...).
- status_code 는 `Integer`.
- Content-Length 값은 raw String 그대로 headers 에 들어감. crate 가 검증 실패 시 parse 단계에서 ParseError.

### 4.6 테스트 — `test/test_message.rb` 신규

```ruby
# frozen_string_literal: true
require "test_helper"

class TestMessage < Minitest::Test
  INVITE = <<~SIP.gsub("\n", "\r\n")
    INVITE sip:bob@biloxi.example.com SIP/2.0
    Via: SIP/2.0/UDP pc33.atlanta.example.com;branch=z9hG4bK776asdhds
    Max-Forwards: 70
    To: Bob <sip:bob@biloxi.example.com>
    From: Alice <sip:alice@atlanta.example.com>;tag=1928301774
    Call-ID: a84b4c76e66710
    CSeq: 314159 INVITE
    Contact: <sip:alice@pc33.atlanta.example.com>
    Content-Length: 0

  SIP

  def test_parse_invite
    h = TsipParser::Message.parse(INVITE)
    assert_equal :request, h[:kind]
    assert_equal "INVITE", h[:method]
    assert_equal "sip:bob@biloxi.example.com", h[:request_uri]
    assert_equal "SIP/2.0", h[:sip_version]
    assert_equal "70", h[:headers]["Max-Forwards"].first
    assert_equal ["a84b4c76e66710"], h[:headers]["Call-ID"]
    assert_equal Encoding::ASCII_8BIT, h[:body].encoding
    assert_equal "".b, h[:body]
  end

  def test_parse_response_with_reason_phrase
    raw = "SIP/2.0 404 Not Found\r\nCall-ID: x\r\n\r\n"
    h = TsipParser::Message.parse(raw)
    assert_equal :response, h[:kind]
    assert_equal 404, h[:status_code]
    assert_equal "Not Found", h[:reason_phrase]
  end

  def test_compact_form_canonicalised
    raw = "INVITE sip:x@h SIP/2.0\r\nv: SIP/2.0/UDP h;branch=z\r\ni: abc\r\nl: 0\r\n\r\n"
    h = TsipParser::Message.parse(raw)
    assert h[:headers].key?("Via")
    assert_equal ["abc"], h[:headers]["Call-ID"]
    assert_equal ["0"], h[:headers]["Content-Length"]
  end

  def test_multiple_via_preserves_order
    raw = "INVITE sip:x@h SIP/2.0\r\n" \
          "Via: SIP/2.0/UDP a;branch=1\r\n" \
          "Via: SIP/2.0/UDP b;branch=2\r\n" \
          "Via: SIP/2.0/UDP c;branch=3\r\n" \
          "\r\n"
    vias = TsipParser::Message.parse(raw)[:headers]["Via"]
    assert_equal 3, vias.size
    assert_includes vias[0], "a"
    assert_includes vias[1], "b"
    assert_includes vias[2], "c"
  end

  def test_body_extracted
    raw = "MESSAGE sip:x@h SIP/2.0\r\nContent-Length: 5\r\n\r\nhello"
    h = TsipParser::Message.parse(raw)
    assert_equal "hello".b, h[:body]
  end

  def test_raises_parse_error_on_malformed
    assert_raises(TsipParser::ParseError) do
      TsipParser::Message.parse("not a sip message")
    end
  end

  def test_raises_on_negative_content_length
    raw = "MESSAGE sip:x@h SIP/2.0\r\nContent-Length: -1\r\n\r\n"
    assert_raises(TsipParser::ParseError) do
      TsipParser::Message.parse(raw)
    end
  end
end
```

## 5. tsip-core 측 통합 (별도 릴리스, 이 문서 범위 밖)

gem v0.3.0 publish 후 tsip-core 에서:

```ruby
# lib/tsip_core/sip/tsip_parser_bridge.rb 에 Parser override 추가
if defined?(TsipParser::Message)
  module TsipCore::Sip::Parser
    def self.parse(raw)
      h = TsipParser::Message.parse(raw.is_a?(String) ? raw : raw.to_s)
      msg = if h[:kind] == :request
        Request.new(
          method: h[:method],
          request_uri: h[:request_uri],
          sip_version: h[:sip_version],
        )
      else
        Response.new(
          sip_version: h[:sip_version],
          status_code: h[:status_code],
          reason_phrase: h[:reason_phrase],
        )
      end
      msg.instance_variable_set(:@headers, h[:headers])
      msg.body = h[:body]
      msg
    rescue TsipParser::ParseError => e
      raise ParseError, e.message
    end
  end
end
```

핵심 포인트 (crate 핸드오프 §5.1 참조):
- `@headers = h[:headers]` 로 직접 할당 → Ruby `add_header` 루프 skip (stackprof 상 3.1% self 제거).
- canonical name 은 Rust 에서 이미 적용 → Ruby `Headers.canonical` (2.4% self) 회피.
- `Parser.parse_start_line` (2.7%) 도 증발.

**이 세 프레임 합계 8.2% + 간접 효과** — bridge v0.2.3 의 7,239 cps 가 **~7,700~8,000 cps** 구간으로 진입 기대.

## 6. 릴리스 순서 / 체크리스트

1. [ ] `ext/tsip_parser/Cargo.toml` `tsip-parser = "0.3"` 로 bump
2. [ ] `ext/tsip_parser/src/message.rs` 작성 (§4.1)
3. [ ] `ext/tsip_parser/src/lib.rs` 에 `mod message` + `message::init` 등록 (§4.2)
4. [ ] `rake compile` 통과 확인
5. [ ] Ruby irb 에서 smoke — `TsipParser::Message.parse(...)[:body].encoding` 로 ASCII-8BIT 여부 검증. UTF-8 면 §4.4 facade 추가.
6. [ ] `test/test_message.rb` (§4.6) 추가 + `rake test` 녹색
7. [ ] `lib/tsip_parser.rb` 에 `require_relative "tsip_parser/message"` (facade 쓸 경우)
8. [ ] `lib/tsip_parser/version.rb` → `"0.3.0"`
9. [ ] `CHANGELOG.md` 에 `## 0.3.0 — 2026-04-XX` 섹션: `TsipParser::Message.parse` 노출, canonical header 정규화, Content-Length 검증
10. [ ] `README.md` 에 `Message.parse` 사용 예 1블록 추가
11. [ ] `gem build tsip_parser.gemspec`
12. [ ] `gem push tsip_parser-0.3.0.gem`
13. [ ] tsip-core 측 bridge 확장 (§5) — 별도 세션

## 7. 리스크 / 주의

### 7.1 Body encoding
magnus `RString::from_slice` / `RString::new(&[u8])` 의 기본 encoding 은 버전에 따라 다름. `rake compile` 직후 irb 로 실측 → UTF-8 이면 facade 에서 `.b` 호출. 네트워크 전송 단계에서 invalid-UTF-8 string 이 예외를 일으킬 수 있어 ASCII-8BIT 고정 필수.

### 7.2 Headers Hash — 같은 이름 헤더 순서 보존
`build_headers_hash` 는 crate `m.headers` (`Vec<(String, String)>`) 를 원 순서대로 iterate 하면서 `Array<String>` 에 push. Ruby Hash 는 3.1+ 부터 insertion order 보존 — Via 다중 라우팅 depend 하므로 테스트 `test_multiple_via_preserves_order` 필수.

### 7.3 `TsipParser::ParseError` 가 아직 로드 안 된 상태에서 init
`error::parse_error_class` 가 `TsipParser::ParseError` 상수를 runtime 에 lookup. `lib/tsip_parser.rb` 가 extension 로드 전에 ParseError 를 정의 — 기존 경로 그대로. Message init 이 lazy 에러 resolve 를 바꾸지 않음.

### 7.4 `Message.parse` 와 기존 `Address.parse_many` 패턴 차이
gem 의 다른 parse 는 단일 객체/Array 리턴. Message 만 Hash 리턴. 일관성은 낮아지지만 (a) Message 는 field 가 여럿이라 Hash 가 자연스럽고 (b) tsip-core bridge 가 바로 Hash 를 소비해 instance_variable_set 으로 꽂는 게 최속. `Struct` / 전용 class 로 래핑하면 object 할당 오버헤드로 성능 이득 깎임.

### 7.5 Crate path 오버라이드
로컬 dev 중 crate 쪽 버그 발견 시 `ext/tsip_parser/Cargo.toml` 에
```toml
tsip-parser = { version = "0.3", path = "../../sip_uri_crate" }
```
추가해 로컬 수정 반영. **gem push 전에는 path 제거** (path 가 있으면 crates.io 만 참조하는 설치자가 빌드 실패).

## 8. 파일 목록

- 신규: `ext/tsip_parser/src/message.rs`, `test/test_message.rb`
- 수정: `ext/tsip_parser/src/lib.rs` (mod 등록), `ext/tsip_parser/Cargo.toml` (crate 0.3), `lib/tsip_parser.rb` (선택: facade require), `lib/tsip_parser/version.rb` (0.3.0), `CHANGELOG.md`, `README.md`
- 선택: `lib/tsip_parser/message.rb` (body encoding facade)

## 9. 참고 — crate 측 확인된 사항

crate v0.3.0 로컬 검증 결과 (2026-04-19):
- test: 98 passed / 0 failed (address 11 + class 8 + **message 48** + roundtrip 3 + uri 28 + doc 0)
- fuzz: `cargo +nightly fuzz run message` 30s / 4.78M runs / panic=0
- bench: `message_parse_invite_10h` 1.48 μs, `message_parse_response_200` 1.03 μs, `message_parse_compact_invite` 1.06 μs
- git: `db9d646 Release 0.3.0: SIP Message framing parser` (main, pushed)
- crates.io: `tsip-parser 0.3.0` published

---

작성자: crate v0.3.0 릴리스 담당
다음 세션 작업자: gem 측 릴리스 담당
종료 조건: `tsip_parser 0.3.0` rubygems.org publish + tsip-core bridge Parser override 측정 완료
