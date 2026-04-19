# tsip_parser gem v0.2.3 핸드오프 — `TsipParser::Address.new` allocator 노출

작성일: 2026-04-19
대상 gem: `tsip_parser` v0.2.2 → v0.2.3
대상 crate: `tsip-parser` / `sip_uri_crate` (unchanged, `Address` 는 이미 `#[derive(Default)]`)
연관 문서:
- `tsip_parser_gem/docs/V0_2_2_HANDOFF.md` — 직전 릴리스 (Uri class method 3종 노출)
- `tsip_parser_gem/docs/HANDOVER.md` — gem 원 설계
- `tsip-core/docs/TSIP_PARSER_INTEGRATION_HANDOFF.md` — class-alias 전환 계획
- `tsip-core/docs/PERFORMANCE_HANDOVER.md` — 10차 세션 bench 결과 (2026-04-19)

## 1. 배경 한 줄

v0.2.2 로 tsip-core class-alias 전환이 가능해져 **원격 tj 박스에서
−2.8% → +5.7%** 로 회귀 반전 확인. 다만 **목표(cps 8,000+) 미달** — 현 bridge 의
`Address.build` 가 `TsipParser::Address.new` 를 호출할 수 없어 placeholder
`parse("<sip:_@_>")` 로 우회하고 있음 (다이얼로그 당 2회, 8k cps 기준 16k
placeholder parse/s). v0.2.3 는 **magnus 바인딩 1~2줄 추가**로 해결.

## 2. 현 상태 — v0.2.2 에서 `.new` 동작

```ruby
TsipParser::Address.new
# => TypeError: allocator undefined for TsipParser::Address
```

원인: `ext/tsip_parser/src/address.rs:77-88` `init()` 에서 `define_class` 만
호출, `define_alloc_func` / `define_singleton_method("new", ...)` 둘 다 미등록.
magnus `#[magnus::wrap]` 은 TypedData 래퍼만 만들고 allocator 는 등록하지 않음.

Uri 도 동일하게 allocator 없음 (`uri.rs:177`) 이지만 tsip-core 는 Uri 를 항상
`parse()` 로 구성하므로 이번 릴리스 범위는 **Address 만**.

## 3. 변경 — `ext/tsip_parser/src/address.rs`

### 3.1 `Address::empty` 추가

```rust
impl Address {
    fn empty() -> Self {
        Self { inner: tsip_parser::Address::default() }
    }
    // ... existing methods
}
```

`tsip_parser::Address` 는 이미 `sip_uri_crate/src/address.rs:16` 에서
`#[derive(Debug, Clone, PartialEq, Eq, Default)]`. 그래서 Rust 쪽 변경 없음.

### 3.2 singleton method `new` 등록

```rust
pub fn init(ruby: &Ruby, parent: &RModule) -> Result<(), Error> {
    let class = parent.define_class("Address", ruby.class_object())?;
    class.define_singleton_method("new", function!(Address::empty, 0))?;  // ← 추가
    class.define_singleton_method("parse", function!(Address::parse, 1))?;
    // ... 기존
}
```

**주의**: `define_alloc_func` 를 쓰는 것이 Ruby-관용적이지만, magnus 에서 TypedData
allocator 를 직접 노출하려면 trait impl 이 필요해 작업량 증가. `define_singleton_method("new")` 로 0-arg `.new` 를 오버라이드하는 쪽이 최소
침습. 후자는 `.new("...")` 등 다른 아리티 호출이 오면 ArgumentError 가 나는데,
tsip-core 사용 패턴 상 문제 없음. (Ruby facade 는 `lib/tsip_parser/address.rb` 가
이미 setter 기반이라 `.new` 로 추가 상태 주입하는 경로 없음.)

### 3.3 Ruby facade 확인 — `lib/tsip_parser/address.rb`

setter (`display_name=`, `uri=`) 및 `params` 접근이 이미 정의되어 있어야 `.new`
직후 빈 인스턴스에 값을 주입할 수 있음. v0.2.2 facade 가 이미 이를 제공
(tsip-core bridge 가 현재 placeholder 뒤에 호출하는 setter 들이 모두 동작).
따라서 facade 변경 없음.

### 3.4 테스트 추가 — `test/test_address.rb`

```ruby
def test_new_returns_empty_address
  a = TsipParser::Address.new
  assert_nil a.display_name
  assert_nil a.uri
  assert_equal({}, a.params)
  assert_equal "<sip:@>", a.to_s  # 또는 empty 상태의 to_s 계약 확인
end

def test_new_accepts_setters
  a = TsipParser::Address.new
  a.display_name = "Alice"
  a.uri = TsipParser::Uri.parse("sip:alice@example.com")
  a.params["tag"] = "xyz"
  assert_equal '"Alice" <sip:alice@example.com>;tag=xyz', a.to_s
end
```

empty Address 의 `to_s` 가 어떻게 렌더될지 crate 구현에 의존 — 미리 확인해서
assertion 을 맞추거나, 두 번째 테스트만 강한 계약으로 남기고 첫 번째는 `nil` /
`{}` 검증만 유지.

## 4. tsip-core 측 영향 — bridge 간소화

v0.2.3 릴리스 후 `tsip-core/lib/tsip_core/sip/tsip_parser_bridge.rb` 의
`Address.build` 는 placeholder parse 제거 가능:

```ruby
# Before (v0.2.2)
BUILD_TEMPLATE = "<sip:_@_>"
def self.build(display_name: nil, uri: nil, params: nil)
  a = parse(BUILD_TEMPLATE)   # ← placeholder parse
  a.display_name = display_name if display_name
  a.uri = uri if uri
  if params
    target = a.params
    params.each { |k, v| target[k] = v }
  end
  a
end

# After (v0.2.3)
def self.build(display_name: nil, uri: nil, params: nil)
  a = new                     # ← pure empty allocation
  a.display_name = display_name if display_name
  a.uri = uri if uri
  if params
    target = a.params
    params.each { |k, v| target[k] = v }
  end
  a
end
```

tsip-core 측 수정은 2줄 (상수 제거 + parse → new).

## 5. 기대 성능 효과

8k cps 기준 Address.build 호출률 × 제거되는 작업:

| 지표 | v0.2.2 | v0.2.3 expected |
|------|--------|-----------------|
| Address.build 호출/s (8k cps × 2/dialog) | ~16,000 | ~16,000 |
| 호출당 작업 | placeholder parse (string lex + default 생성) + setter | default 생성 + setter |
| parse 제거로 회수되는 CPU/call | ~1-3 μs 예상 | — |
| cps 기대 상승 | — | **+1~3%** (7,200 → 7,400~7,600) |

단독으로 8k 돌파에는 부족 — Parser.parse 네이티브화 (v0.3.x) 와 합쳐져야 목표
도달. 그러나 "easy win" 으로 분류, Parser 네이티브화 전에 체리픽.

## 6. 릴리스 체크리스트

1. [ ] `address.rs::init()` 에 `define_singleton_method("new", ...)` 추가
2. [ ] `Address::empty` impl 추가
3. [ ] `test/test_address.rb` 에 new 테스트 2건 추가
4. [ ] `rake compile && rake test` — gem 단위 회귀 통과
5. [ ] `version.rb` → `0.2.3`
6. [ ] CHANGELOG/README 업데이트 (선택: `Address.new` 노출 한 줄)
7. [ ] `gem build && gem push`
8. [ ] tsip-core 측 `tsip_parser_bridge.rb` §4 대로 간소화 + `bundle update tsip_parser`
9. [ ] 원격 tj 박스에서 인터리브 bench 재측정 (TSIP_PARSER_INTEGRATION_HANDOFF.md §3.3 부록 A 스크립트)

## 7. 비목표

- `TsipParser::Uri.new` 노출 — tsip-core 에서 Uri 는 항상 `parse()` 로 구성. 필요 시
  별도 릴리스.
- `define_alloc_func` / `TypedData` allocator 를 Ruby-관용대로 등록 — 작업량 대비
  이득 없음. `.new` singleton override 로 충분.
- `Address.new(display_name: ..., uri: ..., params: ...)` 키워드 생성자 — tsip-core
  는 이미 `.build` 래퍼 (bridge 내) 로 키워드 변환. 네이티브 쪽은 0-arg 로 단순화
  유지.

## 8. 리스크

| 리스크 | 가능성 | 대응 |
|--------|-------|------|
| empty Address 의 `to_s` 가 crate 에서 panic | 매우 낮음 | `Display` impl 이 `{}` params, `""` uri 에서도 무사해야 함. crate 테스트로 선확인 |
| `.new` 로 만든 Address 의 `params` setter 경로가 rust_params 재호출마다 새 Hash 를 리턴 | 낮음 | Ruby facade 가 `@params` 로 memoize — facade 경로 그대로 |
| magnus `function!(...,0)` 가 0-arg singleton 으로 올바로 노출 안 됨 | 매우 낮음 | 기존 `parse` 가 1-arg singleton 으로 동작 — 동일 매크로 경로 |

## 9. 참고 — 측정 환경

- 로컬: macOS M1, Ruby 4.0.1 (mise)
- 원격 tj: `deploy@182.218.228.52` (Tailscale `100.68.78.105`), Ruby 4.0.1
- 현 gem 설치: 로컬/원격 모두 `tsip_parser 0.2.2`
- 10차 tj bench (2026-04-19): OFF mean 6,797 cps / ON mean 7,183 cps / **+5.7%**

---

작성자: tsip-core class-alias 전환 담당 (10차 세션)
다음 세션 작업자: gem 측 릴리스 담당
종료 조건: v0.2.3 rubygems.org 배포 + tsip-core bridge `.build` placeholder 제거
  + 원격 cps re-measure
