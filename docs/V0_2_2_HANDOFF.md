# tsip_parser gem v0.2.2 핸드오프 — tsip-core class alias 전환용 클래스 메서드 3종 노출

작성일: 2026-04-19
대상 gem: `tsip_parser` v0.2.1 → v0.2.2
대상 crate: `tsip-parser` (unchanged, 0.2.x 그대로 사용)
연관 문서:
- `tsip_parser_gem/docs/HANDOVER.md` — gem 원 설계
- `sip_uri_crate/docs/V0_2_1_HANDOFF.md` — 바로 앞 릴리스 (crate 측)
- `tsip-core/docs/TSIP_PARSER_CRATE_HANDOVER.md` — integration 배경

## 1. 배경 한 줄

v0.2.1 에서 parity (#13 `<evil>`) + Ruby facade escape 일관성을 달성했으나,
tsip-core 통합 벤치에서 **bridge shim 오버헤드로 throughput −2.8% 회귀** 확인
(2026-04-19 측정). 원인은 tsip-core 측 `TsipCore::Sip::Uri.new(scheme:, user:, ...)`
eager field-copy shim. 해결책은 **tsip-core 가 `TsipCore::Sip::Uri =
TsipParser::Uri` 클래스 alias 로 전환**하는 것인데, 이를 위해 gem 이 노출해야 할
클래스 메서드 3종이 현재 미바인딩.

v0.2.2 는 **gem 측 magnus 바인딩 3줄 추가**가 전부. crate 측 변경은 없음.

## 2. 확인 — crate 측 Rust 함수는 이미 존재

`sip_uri_crate/src/uri.rs` 의 public API:

```rust
impl Uri {
    pub fn parse(input: &str) -> Result<Self, ParseError>                       // line 46  — v0.1.0부터
    pub fn parse_range(input: &str, from: usize, to: usize) -> Result<Self, …>  // line 55  — v0.1.0부터
    pub fn parse_param(raw: &str, target: &mut Vec<(String, String)>) -> …      // line 194 — v0.2.0부터
    pub fn parse_host_port(hp: &str) -> Result<(String, Option<u16>), …>         // line 202 — v0.2.0부터
    // … (append_to, transport, aor, host_port, bracket_host 등)
}
```

gem 의 `ext/tsip_parser/Cargo.toml` 이 `tsip-parser = "0.2"` 를 pull 하고
있으므로 v0.2.1 (또는 이후) 의 위 함수들 전부 접근 가능. **crate 재릴리스 불필요**.

## 3. 작업 — gem 측만

### 3.1 `ext/tsip_parser/src/uri.rs` — magnus wrapper 추가

현재 파일 (136 줄) 은 `parse`/`parse_many` singleton + 다수 instance method 를
노출. 아래 3개 wrapper 함수 + init 블록의 `define_singleton_method` 3줄 추가.

#### 3.1.1 `parse_range`

tsip-core `Address.parse` 가 내부에서 `Uri.parse_range(str, lt_idx+1, gt_idx)` 호출
(RFC 3261 name-addr `<...>` 내부 URI 를 substring alloc 없이 파싱).

```rust
fn parse_range(input: RString, from: usize, to: usize) -> Result<Self, Error> {
    let ruby = unsafe { Ruby::get_unchecked() };
    let bytes = unsafe { input.as_slice() };
    let s = std::str::from_utf8(bytes)
        .map_err(|_| Error::new(crate::error::parse_error_class(&ruby), "invalid UTF-8"))?;
    // 바운드 체크 — Ruby 쪽에서 str.bytesize 초과 offset 이 넘어올 수 있음
    if to > s.len() || from > to {
        return Err(Error::new(
            crate::error::parse_error_class(&ruby),
            "parse_range: offset out of bounds",
        ));
    }
    let u = tsip_parser::Uri::parse_range(s, from, to)
        .map_err(|e| crate::error::to_ruby(&ruby, e))?;
    Ok(Uri { inner: u })
}
```

init:
```rust
class.define_singleton_method("parse_range", function!(Uri::parse_range, 3))?;
```

**주의: UTF-8 경계**. `from`/`to` 가 multi-byte 문자 중간이면 `&s[from..to]` 슬라이스가
panic. tsip-parser 의 `parse_range` 가 `&str` 받으므로 내부에서 경계 검증해야 안전.
현재 Rust 함수가 byte-level indexing 이라면 validate 후 슬라이스할 것. 필요 시 crate 측
API 문서에 명시 (실제 tsip-core 호출처는 항상 `index("<") + 1` / `index(">")` 결과를
넘겨 ASCII 경계라 실무상 안전하지만 방어적 체크 권장).

#### 3.1.2 `parse_param`

tsip-core `Via.parse` (line 32) 가 각 param segment 문자열을 넘겨 받아 target Hash 에
key/value 를 삽입:

```ruby
parts.each { |p| Uri.parse_param(p, params) }
```

Rust wrapper:
```rust
fn parse_param(raw: RString, target: RHash) -> Result<(), Error> {
    let ruby = unsafe { Ruby::get_unchecked() };
    let bytes = unsafe { raw.as_slice() };
    let s = std::str::from_utf8(bytes)
        .map_err(|_| Error::new(crate::error::parse_error_class(&ruby), "invalid UTF-8"))?;
    let mut v: Vec<(String, String)> = Vec::with_capacity(1);
    tsip_parser::Uri::parse_param(s, &mut v)
        .map_err(|e| crate::error::to_ruby(&ruby, e))?;
    for (k, val) in v {
        target.aset(k, val)?;
    }
    Ok(())
}
```

init:
```rust
class.define_singleton_method("parse_param", function!(Uri::parse_param, 2))?;
```

**의미론**:
- `raw` 가 빈 문자열이면 Rust 함수는 Ok(()) 반환, target 미변경. Ruby 테스트에서도 no-op 기대.
- `raw` 가 `"transport"` (= 없음) 이면 target["transport"] = "" 삽입 (Ruby 구현과 동일).
- 중복 key 면 마지막 값 덮어씀 (Hash 기본 동작).

#### 3.1.3 `parse_host_port`

tsip-core `Via.parse` (line 30):
```ruby
host, port = Uri.parse_host_port(match[4].strip)
```

Rust wrapper:
```rust
fn parse_host_port(hp: RString) -> Result<(String, Option<u16>), Error> {
    let ruby = unsafe { Ruby::get_unchecked() };
    let bytes = unsafe { hp.as_slice() };
    let s = std::str::from_utf8(bytes)
        .map_err(|_| Error::new(crate::error::parse_error_class(&ruby), "invalid UTF-8"))?;
    tsip_parser::Uri::parse_host_port(s)
        .map_err(|e| crate::error::to_ruby(&ruby, e))
}
```

init:
```rust
class.define_singleton_method("parse_host_port", function!(Uri::parse_host_port, 1))?;
```

magnus 0.8 에서 `(String, Option<u16>)` tuple 반환은 Ruby Array `[String, Integer|nil]`
로 자동 변환됨. tsip-core 사용 패턴 (`host, port = Uri.parse_host_port(...)`) 에
그대로 부합.

**port 타입**: Ruby 측은 Integer 기대. Rust `u16` → Ruby Integer 변환은 magnus 기본
지원. None → nil.

### 3.2 init 블록 최종 형태

`ext/tsip_parser/src/uri.rs:117-136` 의 init 함수 수정 예시:

```rust
pub fn init(ruby: &Ruby, parent: &RModule) -> Result<(), Error> {
    let class = parent.define_class("Uri", ruby.class_object())?;
    class.define_singleton_method("parse", function!(Uri::parse, 1))?;
    class.define_singleton_method("parse_many", function!(Uri::parse_many, 1))?;
    // v0.2.2: tsip-core class-alias integration 용 3종
    class.define_singleton_method("parse_range", function!(Uri::parse_range, 3))?;
    class.define_singleton_method("parse_param", function!(Uri::parse_param, 2))?;
    class.define_singleton_method("parse_host_port", function!(Uri::parse_host_port, 1))?;
    class.define_method("param", method!(Uri::param, 1))?;
    // ... 나머지 기존 method 들 유지
}
```

### 3.3 (선택) Address 측 보완 — skip 권장

tsip-core in_dialog.rb / routing.rb 의 `Address.new(display_name:, uri:, params:)`
호출은 class-alias 후 `NoMethodError` 가능성. 두 가지 대응:

- **권장 (skip)**: tsip-core 쪽에서 `Address.build(...)` helper 를 monkey-patch 로
  추가. 4개 호출처만 이름 변경. gem 작업 없음.
- 대안 (gem 변경): `TsipParser::Address.new(display_name: nil, uri: nil, params: nil)`
  키워드 생성자 지원. magnus 에서 kwargs 파싱 + RHash → Vec 변환 필요. 작업량 ~2h.

`V0_2_1_HANDOFF.md §3.3` 에서 이미 skip 결론. 본 v0.2.2 도 동일 방침. **포함 안 함**.

## 4. 테스트 추가

### 4.1 `test/test_uri_class_methods.rb` (신규)

```ruby
require "test_helper"
require "tsip_parser"

class TsipParserUriClassMethodsTest < Minitest::Test
  def test_parse_range_slices_inner_uri
    full = "<sip:alice@host:5060>"
    u = TsipParser::Uri.parse_range(full, 1, full.bytesize - 1)
    assert_equal "alice", u.user
    assert_equal "host", u.host
    assert_equal 5060, u.port
  end

  def test_parse_range_empty_returns_default
    u = TsipParser::Uri.parse_range("sip:", 0, 4)
    assert_equal "sip", u.scheme
    assert_equal "", u.host
  end

  def test_parse_range_out_of_bounds_raises
    assert_raises(TsipParser::ParseError) do
      TsipParser::Uri.parse_range("sip:a@h", 0, 100)
    end
  end

  def test_parse_param_inserts_key_value
    target = {}
    TsipParser::Uri.parse_param("transport=tls", target)
    assert_equal({ "transport" => "tls" }, target)
  end

  def test_parse_param_key_only
    target = {}
    TsipParser::Uri.parse_param("lr", target)
    assert_equal({ "lr" => "" }, target)
  end

  def test_parse_param_empty_noop
    target = {}
    TsipParser::Uri.parse_param("", target)
    assert_equal({}, target)
  end

  def test_parse_host_port_simple
    assert_equal ["example.com", 5060], TsipParser::Uri.parse_host_port("example.com:5060")
  end

  def test_parse_host_port_no_port
    assert_equal ["example.com", nil], TsipParser::Uri.parse_host_port("example.com")
  end

  def test_parse_host_port_ipv6
    assert_equal ["::1", 5060], TsipParser::Uri.parse_host_port("[::1]:5060")
  end

  def test_parse_host_port_ipv6_no_port
    assert_equal ["::1", nil], TsipParser::Uri.parse_host_port("[::1]")
  end

  def test_parse_host_port_empty
    assert_equal ["", nil], TsipParser::Uri.parse_host_port("")
  end
end
```

### 4.2 기존 테스트 회귀 확인

- `rake test` 전부 통과 (기존 25 + 신규 ~10)
- 기존 `parse` / `parse_many` / instance method 동작 불변

### 4.3 Ruby 측 smoke

```bash
ruby -rtsip_parser -e '
puts TsipParser::VERSION
puts TsipParser::Uri.respond_to?(:parse_range)
puts TsipParser::Uri.respond_to?(:parse_param)
puts TsipParser::Uri.respond_to?(:parse_host_port)

# tsip-core Via.parse 패턴
h, p = TsipParser::Uri.parse_host_port("atlanta.example.com:5060")
puts "h=#{h.inspect} p=#{p.inspect}"

# tsip-core Address.parse_bare_range 패턴
full = "<sips:alice@atlanta.example.com:5061;transport=tls>"
u = TsipParser::Uri.parse_range(full, 1, full.bytesize - 1)
puts "#{u.scheme}://#{u.user}@#{u.host}:#{u.port} params=#{u.params.inspect}"
'
```

기대:
```
0.2.2
true
true
true
h="atlanta.example.com" p=5060
sips://alice@atlanta.example.com:5061 params={"transport"=>"tls"}
```

## 5. 릴리스 체크리스트

1. §3.1 wrapper 함수 3개 + §3.2 init 추가 (`ext/tsip_parser/src/uri.rs`)
2. §4.1 테스트 파일 추가
3. `rake compile` — 빌드 clean
4. `rake test` — 25 + 10 = ~35 passed
5. §4.3 smoke 3 줄 true + 2 출력 확인
6. `Cargo.toml` (gem 자체 `ext/tsip_parser/Cargo.toml`) 0.1.0 → 0.2.2 (crate dep 은
   `tsip-parser = "0.2"` 그대로)
7. `tsip_parser.gemspec` 버전 bump → 0.2.2
8. `CHANGELOG.md`:
   ```
   ## 0.2.2 — 2026-MM-DD
   - NEW: `TsipParser::Uri.parse_range(str, from, to)`, `.parse_param(raw, hash)`,
     `.parse_host_port(hp)` singleton methods exposed. Enables tsip-core to
     swap its pure-Ruby Uri/Address with `TsipCore::Sip::Uri = TsipParser::Uri`
     class alias, eliminating the per-parse bridge shim overhead.
   - No crate-level changes; `tsip-parser = "0.2"` (unchanged).
   ```
9. `gem build tsip_parser.gemspec` → `gem push pkg/tsip_parser-0.2.2.gem`
10. GitHub 태그 `v0.2.2`

## 6. 예상 작업 시간

- §3.1 wrapper 3개: 45m (magnus 타입 시그니처 맞추기 + UTF-8/바운드 체크)
- §3.2 init: 5m
- §4 테스트: 30m
- §4.3 smoke: 10m
- 빌드/릴리스: 30m

총 **~2h**.

## 7. 리스크

| 리스크 | 가능성 | 대응 |
|--------|-------|------|
| `parse_range` 의 from/to 가 UTF-8 경계 아닌 offset 으로 들어와 panic | 낮음 (실호출처 ASCII 경계) | 바운드 체크 + UTF-8 boundary 검증. crate 함수가 이미 byte-safe 면 추가 작업 없음 |
| `parse_param` 의 target 이 `Hash` 외 타입 (Struct 등) 으로 호출 | 매우 낮음 | magnus `RHash::try_convert` 가 안 맞으면 TypeError 자동 raise |
| `parse_host_port` 의 port 범위(u16) 초과 입력 | 중간 | crate 함수가 이미 parse 실패로 반환. magnus 바인딩에서 추가 체크 불필요 |
| 릴리스 후 tsip-core 의 class alias 가 예상 밖 경로에서 NoMethodError | 중간 | V0_2_1_HANDOFF §7 의 tsip-core 측 작업 체크리스트 (is_a?, Address.build 등) 순서대로 확인 |

## 8. 릴리스 후 tsip-core 측 후속 (본 gem scope 밖)

v0.2.2 publish 이후 tsip-core 저장소에서 (이전 V0_2_1_HANDOFF §7 재게시):

1. `lib/tsip_core/sip/tsip_parser_bridge.rb` 를 class alias 로 교체:
   ```ruby
   require "tsip_parser"
   module TsipCore
     module Sip
       remove_const(:Uri) if const_defined?(:Uri, false)
       remove_const(:Address) if const_defined?(:Address, false)
       Uri = TsipParser::Uri
       Address = TsipParser::Address
     end
   end
   ```
2. `Address.new(display_name:, uri:, params:)` 호출 4지점 (`in_dialog.rb:16-17`,
   `routing.rb:30,45`) 을 `Address.build(...)` helper 로 교체. helper 정의:
   ```ruby
   class TsipParser::Address
     def self.build(display_name: nil, uri: nil, params: nil)
       a = new
       a.display_name = display_name if display_name
       a.uri = uri if uri
       params&.each { |k, v| a.params[k] = v }
       a
     end
   end
   ```
3. `TSIP_PARSER=1 bundle exec rake test` → 197/470 통과 재확인
4. 원격 tj 재측정 — cycle 1 clean baseline 7,784 cps 기준 +5~10% 목표

## 9. 비목표

- Address kwargs 생성자 gem 측 지원 — skip (§3.3)
- crate 버전 bump — 불필요
- Parser.parse 네이티브화 — 별도 로드맵 (v0.3.x)

---

작성자: tsip-parser integration 벤치 담당 (tsip-core 측)
검토 대상: tsip_parser gem 유지자
다음 핸드오프 (있다면): v0.2.3 — Address.new kwargs 생성자 (tsip-core 쪽에서
Address.build helper 로 우회 결정 시 이 핸드오프는 불필요)
