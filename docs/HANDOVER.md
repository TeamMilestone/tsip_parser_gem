# tsip_parser gem 구현 핸드오버

작성일: 2026-04-19. 목적: crates.io 에 공개된 Rust 크레이트
[`tsip-parser`](https://crates.io/crates/tsip-parser) (v0.1.0, MIT) 를 Ruby
gem 으로 감싸 `TsipParser::Uri`, `TsipParser::Address` API 를 제공한다.
`magnus` + `rb_sys` 기반 네이티브 익스텐션. 이 문서는 gem **자체** 의 설계·
구현 지침.

---

## 0. 배경

`tsip-parser` 크레이트는 tsip-core Ruby 구현의 Uri/Address 파서를 pure-Rust
로 포팅한 결과물이다 (레포: `TeamMilestone/tsip-parser`). 크레이트 자체는
FFI 비의존이고, Ruby 통합은 별도 얇은 바인딩 레이어로 제공하기로 결정되어
있음 (`sip_uri_crate/docs/HANDOVER.md §8` 참조).

본 gem 의 목적은:

1. tsip-core 의 `TsipCore::Sip::Uri` / `TsipCore::Sip::Address` 를 최대한
   동일한 Ruby API 로 제공하되, 내부 파싱을 Rust 네이티브로 위임.
2. tsip-core 가 `TsipParser` 존재 시 자동 위임하도록 연결하는 경로를
   간단하게 만듦. (tsip-core 측 변경은 본 gem scope 밖.)
3. `stone_smith` / `stone-webrtc` 와 동일한 배포·유지보수 패턴을 따름.

성능 목표 (M1 macOS, release):

- `TsipParser::Uri.parse(str)` ≤ 500 ns (현재 Rust 단독 142 ns + FFI 오버헤드)
- `TsipParser::Address.parse(str)` ≤ 700 ns
- Ruby 현 구현 (5-7 µs) 대비 10× 이상 가속

---

## 1. 범위

### 포함

1. **Rust 네이티브 익스텐션** — `ext/tsip_parser/` 에 magnus 바인딩 crate
2. **Ruby facade 클래스** — `lib/tsip_parser/uri.rb`, `address.rb` 가
   `attr_reader` / `to_s` 등 Ruby-쪽 편의 메서드 제공
3. **tsip-core 호환 `params` / `headers` 인터페이스** — 현재는 `Hash`,
   향후 `Array<[key, val]>` 로 옮겨갈지 여부는 §7 참조
4. **크로스 플랫폼 프리컴파일 바이너리** — rb_sys 의 CI 경로 (stone_smith 가
   이미 쓰는 그 패턴) 그대로 채택

### 제외 (명시적 non-goal)

- SIP 메시지 전체 파싱 (start-line, headers, body) — tsip-core Parser 담당
- Via / CSeq / Contact 헤더 구조화 — 별도 관심사
- 크레이트 자체 기능 확장 — upstream 크레이트에서만 변경, gem 은 thin wrapper

---

## 2. 레퍼런스 구현

### 2.1 Rust 크레이트 (upstream)

- 크레이트: `tsip-parser` v0.1.0 on crates.io
- GitHub: https://github.com/TeamMilestone/tsip-parser
- 공개 타입:
  - `tsip_parser::Uri { scheme, user, password, host, port, params, headers }`
  - `tsip_parser::Address { display_name, uri, params }`
  - `tsip_parser::ParseError` (Empty / UnterminatedBracket / UnterminatedQuote
    / UnterminatedAngle / InvalidScheme / InvalidUtf8)
  - `Uri::parse(&str)`, `Uri::parse_range(&str, from, to)`, `Display` 구현
  - `Address::parse(&str)`, `Display`, `Address::tag() / set_tag()`
- `params` / `headers` 는 `Vec<(String, String)>` — 순서 보존

### 2.2 Ruby 쪽 공개 API 레퍼런스

gem 의 Ruby 표면은 tsip-core 의 공개 API 와 **동등**해야 함 — 통합 시 모듈
스왑 한 줄이면 동작하도록.

| tsip-core | tsip_parser gem | 비고 |
|-----------|-----------------|------|
| `TsipCore::Sip::Uri.parse(str)` | `TsipParser::Uri.parse(str)` | 파싱 |
| `uri.scheme` / `.user` / `.password` / `.host` / `.port` | 동일 | attr_reader |
| `uri.params` / `.headers` | `Hash` (tsip-core 호환) | §7 결정사항 |
| `uri.to_s` | 동일 | round-trip parity |
| `uri.aor` / `.host_port` / `.transport` | 동일 | 편의 메서드 |
| `TsipCore::Sip::Address.parse(str)` | `TsipParser::Address.parse(str)` | |
| `addr.display_name` / `.uri` / `.params` | 동일 | |
| `addr.tag` / `addr.tag = v` | 동일 | |
| `addr.to_s` | 동일 | |

**테스트 레퍼런스**: `tsip-core/test/sip/test_address.rb` (5 테스트) 를 그대로
포팅 — 동일 입력 set 으로 gem 이 통과해야 함. Uri 테스트는 Rust 크레이트의
`tests/uri_parity.rs` (21 개) 를 Ruby 로 옮겨 35 개 이상의 testsuite 목표.

---

## 3. gem 레이아웃 제안

`stone_smith` / `stone-webrtc` 구조를 답습. 이게 가장 안전.

```
tsip_parser_gem/
├── Gemfile
├── Rakefile
├── CHANGELOG.md
├── LICENSE
├── README.md
├── tsip_parser.gemspec
├── docs/
│   └── HANDOVER.md             ← 이 문서
├── ext/
│   └── tsip_parser/
│       ├── Cargo.toml           # magnus + tsip-parser 의존
│       ├── extconf.rb           # rb_sys::create_rust_makefile
│       └── src/
│           ├── lib.rs           # #[magnus::init] → TsipParser 모듈
│           ├── uri.rs           # Uri 바인딩 (Ruby Hash 변환 포함)
│           ├── address.rs       # Address 바인딩
│           └── error.rs         # ParseError → Ruby 예외 매핑
├── lib/
│   ├── tsip_parser.rb           # facade + require 순서
│   └── tsip_parser/
│       ├── version.rb
│       ├── tsip_parser.bundle   # 컴파일 산출물 (gitignore)
│       ├── uri.rb               # Ruby 편의 메서드 (필요시)
│       └── address.rb
├── sig/
│   └── tsip_parser.rbs          # RBS 시그니처 (선택)
├── test/
│   ├── test_helper.rb
│   ├── test_uri.rb              # tsip-core uri 동등성 + 추가
│   └── test_address.rb          # tsip-core test_address.rb 5개 포팅
└── bin/                         # (없음; binary 실행파일 없음)
```

### 3.1 `tsip_parser.gemspec` 초기값

```ruby
# frozen_string_literal: true

require_relative "lib/tsip_parser/version"

Gem::Specification.new do |spec|
  spec.name     = "tsip_parser"
  spec.version  = TsipParser::VERSION
  spec.authors  = ["Team Milestone"]
  spec.email    = ["dev@team-milestone.io"]

  spec.summary     = "RFC 3261 SIP URI and Address parser for Ruby, powered by Rust."
  spec.description = "Thin Ruby binding around the tsip-parser Rust crate. " \
                     "Provides RFC 3261 §19.1 (SIP URI) and §25.1 (Address) " \
                     "parsing and serialization at ~25-35× the speed of the " \
                     "pure-Ruby reference in tsip-core."
  spec.homepage    = "https://github.com/TeamMilestone/tsip_parser_gem"
  spec.license     = "MIT"
  spec.required_ruby_version     = ">= 3.0.0"
  spec.required_rubygems_version = ">= 3.3.11"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.glob(%w[
    lib/**/*.rb
    ext/**/*.{rs,toml,rb}
    sig/**/*.rbs
    CHANGELOG.md
    LICENSE
    README.md
    Cargo.toml
    Cargo.lock
    Rakefile
  ])
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/tsip_parser/extconf.rb"]

  spec.add_dependency "rb_sys", "~> 0.9.91"
end
```

### 3.2 `ext/tsip_parser/Cargo.toml`

```toml
[package]
name = "tsip_parser"
version = "0.1.0"
edition = "2021"
publish = false

[lib]
crate-type = ["cdylib"]

[dependencies]
magnus     = { version = "0.8" }
tsip-parser = "0.1"  # crates.io 공개 버전 고정
```

### 3.3 `ext/tsip_parser/extconf.rb`

```ruby
# frozen_string_literal: true
require "mkmf"
require "rb_sys/mkmf"

create_rust_makefile("tsip_parser/tsip_parser")
```

### 3.4 워크스페이스 루트 `Cargo.toml`

rb_sys 가 기대하는 워크스페이스 배치. stone_smith 루트 `Cargo.toml` 과
동일 패턴:

```toml
[workspace]
members = ["ext/tsip_parser"]
resolver = "2"

[profile.release]
lto = "thin"
codegen-units = 1
opt-level = 3
```

---

## 4. Rust 바인딩 구현 가이드

### 4.1 모듈 초기화 (`ext/tsip_parser/src/lib.rs`)

```rust
use magnus::{Error, Ruby};

mod address;
mod error;
mod uri;

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("TsipParser")?;
    error::init(ruby, &module)?;
    uri::init(ruby, &module)?;
    address::init(ruby, &module)?;
    Ok(())
}
```

### 4.2 Uri 바인딩 원칙

**Ruby 객체 표현**: magnus 로 `TsipParser::Uri` 클래스를 정의하고, 내부에
파싱 결과의 스냅샷을 ivars 로 들고 있음. 각 attr_reader 는 ivar 를 그대로
반환. 이 설계의 장점:

- attr 접근이 Rust 왕복 없이 순수 Ruby 속도
- `Marshal` / `YAML` / `inspect` 등 기본 동작 자연스럽게 작동
- tsip-core 의 `TsipCore::Sip::Uri` 와 완전히 같은 형태로 보임

```rust
// ext/tsip_parser/src/uri.rs (개요)
use magnus::{function, method, Error, Module, RHash, RModule, RString, Ruby, Value};

pub fn init(ruby: &Ruby, parent: &RModule) -> Result<(), Error> {
    let class = parent.define_class("Uri", ruby.class_object())?;
    class.define_singleton_method("parse", function!(parse, 1))?;
    class.define_method("to_s", method!(to_s, 0))?;
    class.define_method("aor", method!(aor, 0))?;
    // ... scheme/user/.. 는 attr_reader 로 처리 (init 시 ivar set)
    Ok(())
}

fn parse(ruby: &Ruby, input: RString) -> Result<Value, Error> {
    let bytes = unsafe { input.as_slice() };
    let s = std::str::from_utf8(bytes)
        .map_err(|_| Error::new(ruby.exception_arg_error(), "invalid UTF-8"))?;
    let uri = tsip_parser::Uri::parse(s)
        .map_err(|e| crate::error::to_ruby(ruby, e))?;
    build_ruby_uri(ruby, uri)
}

fn build_ruby_uri(ruby: &Ruby, u: tsip_parser::Uri) -> Result<Value, Error> {
    let klass = ruby
        .class_object()
        .const_get::<_, magnus::RClass>("TsipParser")?
        .const_get::<_, magnus::RClass>("Uri")?;
    let obj = klass.new_instance(())?;  // no-arg allocator
    obj.ivar_set("@scheme",   RString::new(u.scheme))?;
    obj.ivar_set("@user",     u.user.map(RString::new))?;
    obj.ivar_set("@password", u.password.map(RString::new))?;
    obj.ivar_set("@host",     RString::new(&u.host))?;
    obj.ivar_set("@port",     u.port)?;
    obj.ivar_set("@params",   hash_from_pairs(ruby, &u.params)?)?;
    obj.ivar_set("@headers",  hash_from_pairs(ruby, &u.headers)?)?;
    Ok(obj.into())
}
```

Ruby facade 쪽 (`lib/tsip_parser/uri.rb`) 는 `attr_reader` 선언과 `to_s` /
`aor` 등 일부 편의 메서드 정의만 담당:

```ruby
module TsipParser
  class Uri
    attr_reader :scheme, :user, :password, :host, :port, :params, :headers
    # to_s / aor / host_port / transport 는 Rust 메서드 바인딩으로 제공됨
  end
end
```

### 4.3 Address 바인딩

동일 패턴. `@display_name`, `@uri`, `@params` ivars. `@uri` 필드는 위에서
만든 `TsipParser::Uri` 객체를 재귀적으로 생성해 넣음.

`tag` / `tag=` 는 `@params` Hash 에 접근하는 Ruby 메서드로 충분 — Rust 쪽에
노출할 필요 없음. 즉 gem 의 `Address` 는 Rust에서 초기화된 후에는 순수 Ruby
객체로 동작.

### 4.4 에러 매핑 (`ext/tsip_parser/src/error.rs`)

```rust
use magnus::{exception, Error, Module, RModule, Ruby};

pub fn init(ruby: &Ruby, parent: &RModule) -> Result<(), Error> {
    parent.define_error("ParseError", ruby.exception_standard_error())?;
    Ok(())
}

pub fn to_ruby(ruby: &Ruby, err: tsip_parser::ParseError) -> Error {
    let msg = err.to_string();
    Error::new(
        ruby.class_object()
            .const_get::<_, magnus::ExceptionClass>("TsipParser::ParseError")
            .unwrap_or_else(|_| ruby.exception_arg_error()),
        msg,
    )
}
```

tsip-core 레퍼런스는 `ArgumentError` 를 던지므로, 호환을 위해 `ParseError`
를 `ArgumentError` 서브클래스로 정의하는 방안도 고려. §7 열린 결정사항.

---

## 5. Ruby facade 구현 가이드

### 5.1 `lib/tsip_parser.rb`

```ruby
# frozen_string_literal: true
require_relative "tsip_parser/version"
require "tsip_parser/tsip_parser"  # 컴파일된 .bundle/.so 로드
require_relative "tsip_parser/uri"
require_relative "tsip_parser/address"

module TsipParser
end
```

### 5.2 tsip-core 와의 호환성 shim (선택)

tsip-core 가 향후 `TsipParser` 모듈 존재 시 자동 위임하도록 바꾸면, 다음과
같은 래퍼를 tsip-core 쪽에 넣게 됨 (본 gem scope 밖 — 참고용):

```ruby
# tsip-core/lib/tsip_core/sip/uri.rb 상단에 추가 예정 형태
module TsipCore
  module Sip
    Uri = TsipParser::Uri if defined?(TsipParser::Uri) && ENV["TSIP_NATIVE"] != "0"
  end
end
```

gem 에서는 tsip-core 를 의존성으로 가지지 **않음**. gem 단독으로도 완전
기능해야 하고, tsip-core 연결은 tsip-core 쪽에서 옵션으로 선택.

---

## 6. 테스트 전략

### 6.1 단위 테스트 (`test/test_uri.rb`, `test/test_address.rb`)

- Minitest 기반 (tsip-core 와 일치)
- `tsip-core/test/sip/test_address.rb` 5 테스트 그대로 이식
- `tsip_parser_crate/tests/uri_parity.rs` 21 테스트 Ruby 로 포팅
- round-trip 테스트: `parse → to_s → parse → 동일` 불변성

### 6.2 성능 검증

`bench/` 디렉토리에 `benchmark-ips` 기반 마이크로 벤치 추가:

```ruby
require "benchmark/ips"
require "tsip_parser"
require "tsip_core"  # 비교 대상

Benchmark.ips do |x|
  x.report("tsip_parser") { TsipParser::Uri.parse("sip:alice@host;transport=tcp") }
  x.report("tsip_core")   { TsipCore::Sip::Uri.parse("sip:alice@host;transport=tcp") }
  x.compare!
end
```

목표: `tsip_parser` 가 `tsip_core` 대비 10× 이상 ips 우위.

### 6.3 크로스 오라클

의심스러운 입력은 tsip-core REPL 결과를 ground truth 로 두고 gem 결과를
비교. 초기 개발 중 실제 INVITE trace 에서 추출한 Uri/Address 문자열
수십 개를 `test/fixtures/uris.txt` 등으로 저장해두면 유용.

---

## 7. 열린 결정 사항

1. **`params` / `headers` 타입**
   - (a) `Hash<String, String>` — tsip-core 호환, 가장 자연스러움
   - (b) `Array<[String, String]>` — Rust 크레이트와 구조 동일, 순서 엄격
   - 권고: **(a)** 로 시작. Ruby ≥ 2.0 Hash 는 insertion order 보존이라
     라운드트립에 충분. tsip-core 와 API 동일.

2. **`ParseError` 클래스 위치**
   - (a) `TsipParser::ParseError < StandardError`
   - (b) `TsipParser::ParseError < ArgumentError` — tsip-core 가 ArgumentError
     던지므로 호환
   - 권고: **(b)**. 기존 tsip-core 코드의 rescue 절과 충돌 없음.

3. **`Uri.parse_range` 노출 여부**
   - tsip-core Ruby 에는 `parse_range(src, from, to)` 가 있음 (Address 파서가
     호출)
   - gem 에서 동일 API 를 제공하면 tsip-core 를 gem 위에 얹기 쉬움
   - 권고: **노출**. Rust 쪽은 이미 지원, FFI 오버헤드만 있음.

4. **프리컴파일 바이너리 플랫폼 매트릭스**
   - stone_smith 는 linux-x64-gnu, linux-arm64, darwin-x64, darwin-arm64 빌드
   - 권고: 동일 매트릭스. CI 설정도 복제.

5. **tsip-core 와의 버전 결합**
   - gem 이 tsip-core 의 특정 버전에 종속되는가? 아니면 독립 버전?
   - 권고: **독립**. gem 은 Rust 크레이트 버전을 따라가고, tsip-core 는
     선택적으로 이 gem 을 사용.

---

## 8. 작업 순서 제안

1. **스캐폴드** (0.5 일)
   - `bundle gem tsip_parser --ext=rust` 로 rb_sys 템플릿 생성 (또는 수동
     레이아웃)
   - `ext/tsip_parser/Cargo.toml` 에 `tsip-parser = "0.1"` 추가
   - `rake compile` 으로 빌드 통과 확인

2. **Uri 바인딩** (0.5 일)
   - `TsipParser::Uri.parse` singleton + attr_reader 세팅
   - `to_s` / `aor` / `host_port` / `transport` 메서드 위임
   - 테스트 10 개 이상

3. **Address 바인딩** (0.5 일)
   - `TsipParser::Address.parse` + ivars
   - `tag` / `tag=` Ruby 메서드
   - tsip-core test_address.rb 5 테스트 포팅 통과

4. **bench + 문서** (0.5 일)
   - `bench/compare.rb`
   - `README.md` + `CHANGELOG.md`
   - 측정 결과 기록

5. **크로스 빌드 CI** (0.5 일)
   - stone_smith 의 `.github/workflows/cross-gem.yml` 참고
   - rubygems.org 배포 리허설 (`gem build` + `gem install ./tsip_parser-*.gem`)

**총 추정**: 2-2.5 일.

---

## 9. 배포

- rubygems.org 계정: stone_smith 배포에 쓰인 `team-milestone` 계정 재사용
- 버전 정책: 크레이트 `tsip-parser` 버전과 동일 major.minor 유지 (예:
  crate 0.1.x ↔ gem 0.1.x). patch 는 각각 독립.
- 최초 릴리스 체크리스트:
  - [ ] `bundle exec rake test` green
  - [ ] `bundle exec rake compile` 로 bundle 산출
  - [ ] `gem build tsip_parser.gemspec`
  - [ ] 로컬 `gem install ./tsip_parser-0.1.0.gem` 으로 설치 확인
  - [ ] `ruby -rtsip_parser -e 'p TsipParser::Uri.parse("sip:a@b").to_s'`
  - [ ] prebuilt binary CI job 녹색
  - [ ] `gem push`

---

## 10. 참조 문서

- 본 Rust 크레이트: `projects/sip_uri_crate/docs/HANDOVER.md`
- Ruby 원본 파서: `projects/tsip-core/lib/tsip_core/sip/{uri,address}.rb`
- magnus 바인딩 패턴: `projects/stone_smith/ext/stone_smith/`
- rb_sys gem 가이드: https://oxidize-rb.github.io/rb-sys/

---

## 11. Non-goals 재확인

- WebRTC / RTP / media — 별도 gem
- TLS / 크립토 — `stone_smith`
- SIP 메시지 상위 레이어 (파서, transaction, dialog) — `tsip-core`
- Rust 크레이트 자체 기능 개선 — upstream 크레이트에서 처리

이 범위를 넘어가는 요청이 들어오면 거부하고 해당 crate/gem 에서 처리.

---

## 끝

- 구현자: (미정)
- 리뷰어: tsip-core / stone_smith 유지보수자
- upstream: https://github.com/TeamMilestone/tsip-parser (crates.io v0.1.0)
- 예상 gem 저장소: `TeamMilestone/tsip_parser_gem`
