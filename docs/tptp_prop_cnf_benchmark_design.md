# TPTP Propositional CNF Subset 성능 비교 설계 초안

## 1. 문서 목적

이 문서는 TPTP Propositional CNF subset 문제를 대상으로 다양한 자료구조와 집합 연산 알고리즘의 성능을 비교하기 위한 구현 방향을 정리한다.

본 프로젝트의 1차 목표는 완성형 SAT solver를 만드는 것이 아니라, CNF 표현과 집합 연산의 핵심 자료구조를 여러 방식으로 구현한 뒤 동일한 입력군에 대해 성능을 비교할 수 있는 실험 기반을 만드는 것이다.

현재 단계의 비교 범위는 CPU 기반 구현으로 제한한다.

## 2. 문제 범위

### 2.1 입력 대상

입력은 TPTP 형식 중 propositional CNF subset만을 대상으로 한다.

허용 범위는 다음과 같다.

- `cnf(name, role, formula).`
- `formula`는 propositional atom, `~`, `|`, 괄호, `$true`, `$false` 로 구성된다.
- atom은 0-항 propositional symbol만 허용한다.

초기 단계에서 제외하는 항목은 다음과 같다.

- `fof`, `tff`, `thf`
- quantifier
- 함수 인자를 갖는 predicate
- equality
- 비명제적 first-order 구조
- 필요 시점 전까지의 `include(...)`

### 2.2 내부 의미

CNF formula는 clause들의 conjunction으로 간주한다.

- clause: literal들의 disjunction
- formula: clause들의 집합 또는 순서 없는 모음

이때 내부 매핑의 기본 단위는 `literal`이 아니라 `propositional variable(atom)`이다.

예를 들어 `p`, `q`, `r`에 대해 인덱스를 부여하면,

- `p`는 `pos` bitset의 `p` 위치를 사용한다.
- `~p`는 `neg` bitset의 `p` 위치를 사용한다.

### 2.3 예제 입력

문서와 구현의 기준점으로 사용할 수 있도록 작은 TPTP Propositional CNF subset 예제를 하나 유지하는 것이 좋다.

다음 예제는 순수 propositional CNF이며, atom은 `p`, `q` 두 개만 사용한다.

```tptp
cnf(c1, axiom, (p | q)).
cnf(c2, axiom, (~p | q)).
cnf(c3, axiom, (p | ~q)).
cnf(c4, axiom, (~p | ~q)).
```

이 예제는 unsatisfiable 하다.

- `p = true, q = true` 이면 `c4`가 거짓이다.
- `p = true, q = false` 이면 `c2`가 거짓이다.
- `p = false, q = true` 이면 `c3`가 거짓이다.
- `p = false, q = false` 이면 `c1`이 거짓이다.

이 예제는 다음 이유로 초기 테스트 입력으로 유용하다.

- 문법이 단순해서 파서 검증 기준으로 쓰기 쉽다.
- atom 인덱싱 예제를 설명하기 쉽다.
- clause 단위 bitset 표현을 직접 확인하기 좋다.
- satisfiable 또는 unsatisfiable 판정 실험의 작은 기준점으로 쓸 수 있다.

위 예제에 대해 `p -> 0`, `q -> 1` 로 매핑하면 각 clause의 내부 표현은 다음처럼 볼 수 있다.

- `c1: (p | q)` -> `pos = {p, q}`, `neg = {}`
- `c2: (~p | q)` -> `pos = {q}`, `neg = {p}`
- `c3: (p | ~q)` -> `pos = {p}`, `neg = {q}`
- `c4: (~p | ~q)` -> `pos = {}`, `neg = {p, q}`

실제 예제 파일은 `examples/prop_cnf_example_001.p` 에 둔다.

## 3. 핵심 설계 원칙

### 3.1 Clause 내부 표현

각 clause는 두 개의 bitset으로 표현한다.

- `pos bitset`: 양의 literal이 포함된 atom 위치
- `neg bitset`: 음의 literal이 포함된 atom 위치

이 방식의 장점은 다음과 같다.

- 중복 literal 제거가 쉽다.
- tautological clause 검사(`pos & neg != 0`)가 빠르다.
- clause equality 비교가 단순하다.
- clause subsumption 검사의 기반 연산을 bitwise 연산으로 구성할 수 있다.

자료형은 `int` 배열보다 `uint64_t` 배열을 기본 후보로 둔다.

### 3.2 Formula 상위 표현

CNF formula는 단순한 raw clause 배열만으로 표현하지 않는다. clause 내부는 bitset으로 유지하되, formula 수준에서는 clause를 직접 비교하는 비용을 줄일 수 있는 구조가 필요하다.

기본 후보는 다음과 같다.

1. clause의 단순 배열 또는 벡터
2. 정렬된 clause 배열
3. hash 기반 clause set
4. clause interning 후 `ClauseId` 기반 정렬 벡터
5. sparse clause 표현을 사용하는 혼합 구조

## 4. 비교 대상 자료구조

### 4.1 후보 A: Dense bitset clause + 단순 배열

구조:

- clause는 `pos/neg uint64_t[]`
- formula는 `Clause[]` 또는 `Clause*[]`

장점:

- 구현이 단순하다.
- 작은 규모 실험의 baseline으로 적합하다.
- clause 단위 bitwise 연산 성능을 직접 확인하기 좋다.

단점:

- formula 간 equality, 차집합, 교집합 계산 시 clause 비교 비용이 커질 수 있다.
- 동일 clause 중복 관리가 비효율적일 수 있다.

### 4.2 후보 B: Dense bitset clause + 정렬된 배열

구조:

- clause 자체는 dense bitset 유지
- formula는 canonical order로 정렬된 clause 배열 유지

장점:

- equality 비교와 병합형 집합 연산이 단순해진다.
- 중복 clause 제거가 쉬워진다.

단점:

- 정렬 비용이 추가된다.
- clause 자체의 비교가 여전히 비쌀 수 있다.

### 4.3 후보 C: Dense bitset clause + hash set

구조:

- clause는 dense bitset
- formula는 hash table 기반 set

장점:

- membership 검사와 중복 제거가 빠르다.
- clause 존재 여부 검사가 평균적으로 효율적이다.

단점:

- 교집합, 차집합, 순서 기반 canonicalization은 별도 전략이 필요하다.
- 해시 품질과 메모리 사용량에 민감하다.

### 4.4 후보 D: Dense bitset clause + clause interning + sorted ClauseId vector

구조:

- 모든 clause는 전역 pool에 intern한다.
- 같은 clause는 하나의 `ClauseId`만 가진다.
- formula는 정렬된 고유 `ClauseId` 배열로 표현한다.

장점:

- clause equality 비용을 크게 줄일 수 있다.
- formula equality, 교집합, 차집합 연산을 `ClauseId` 기준으로 빠르게 수행할 수 있다.
- canonical form 유지가 쉽다.

단점:

- pool과 hash-consing 구현이 필요하다.
- 메모리 관리가 다소 복잡해진다.

현재 기준의 1순위 후보는 이 구조이다.

### 4.5 후보 E: Sparse clause 표현

구조:

- clause를 bitset 대신 정렬된 atom 인덱스 배열로 표현하거나,
- positive/negative literal 목록을 따로 저장한다.

장점:

- atom 수가 매우 크고 clause가 희소할 때 메모리를 절약할 수 있다.
- 짧은 clause 위주의 입력에서는 dense bitset보다 유리할 수 있다.

단점:

- bitwise 연산 기반의 장점이 줄어든다.
- tautology, subsumption, equality 비교의 구현 전략이 달라진다.

이 구조는 dense bitset 방식과의 비교군으로 중요하다.

## 5. 비교해야 할 주요 연산

프로젝트에서 비교 대상이 되는 것은 단순 저장 비용만이 아니라, 실제 CNF 처리에서 반복적으로 호출되는 연산들이다.

### 5.1 Clause 수준

- literal 추가
- literal 중복 제거
- tautological clause 검사
- clause equality 검사
- clause subsumption 검사
- clause hash 계산

### 5.2 Formula 수준

- 동일 clause 존재 여부 검사
- formula equality 검사
- 중복 clause 제거
- 차집합
- 교집합
- 합집합
- subsumption 후보 탐색을 위한 인덱싱

### 5.3 선택적 확장

향후 필요하다면 다음도 포함할 수 있다.

- resolution 후보 탐색
- unit clause 추적
- pure literal 관련 인덱싱
- SAT solving 전처리 단계에서의 정규화

## 6. 성능 비교 관점

비교는 단일 실행 시간만으로 판단하지 않는다. 최소한 다음 항목을 같이 측정해야 한다.

- 파싱 후 내부 구조 생성 시간
- 메모리 사용량
- clause 수 증가에 따른 formula 집합 연산 시간
- atom 수 증가에 따른 clause 연산 시간
- 희소한 문제와 밀집한 문제에서의 성능 차이

### 6.1 입력 특성 축

벤치마크 입력은 다음 축을 기준으로 나누어 보는 것이 좋다.

- atom 수
- clause 수
- clause당 평균 literal 수
- tautological clause 비율
- 중복 clause 비율
- 전체 formula의 희소성 또는 밀집도

### 6.2 결과 해석 시 주의점

어떤 자료구조가 가장 빠른지는 입력 분포에 따라 달라질 수 있다.

- dense bitset은 atom 수가 상대적으로 작거나 clause 길이가 길수록 유리할 가능성이 높다.
- sparse 표현은 atom 수가 크고 clause 길이가 짧을수록 유리할 가능성이 높다.
- formula 수준 집합 연산이 많다면 `ClauseId` 기반 canonical structure가 유리할 가능성이 높다.

## 7. 현재 시점의 권장 기본안

프로젝트의 baseline 구현은 다음처럼 시작하는 것이 좋다.

1. 입력 범위는 TPTP Propositional CNF subset으로 제한한다.
2. atom에만 고유 인덱스를 부여한다.
3. clause는 `pos/neg dense bitset`으로 표현한다.
4. formula는 우선 단순 배열로 시작하되, 비교 실험의 중심 구조는 `ClauseId` 기반 정렬 벡터까지 포함한다.
5. dense bitset 방식과 sparse clause 방식을 반드시 비교군으로 둔다.

즉, 단일 정답 자료구조를 미리 고정하기보다 다음 두 층위를 분리해서 비교하는 것이 중요하다.

- clause 내부 표현
- formula 상위 집합 표현

## 8. 초기 구현 우선순위

### 8.1 1단계

- TPTP Propositional CNF subset 파서 범위 확정
- atom 인덱싱 규칙 확정
- dense bitset clause 구현
- clause hash와 equality 구현
- 예제 파일 기반 파서 테스트 추가

### 8.2 2단계

- formula의 단순 배열 버전 구현
- formula 집합 연산 API 정의
- benchmark harness 초안 작성

### 8.3 3단계

- clause interning + `ClauseId` 구조 구현
- sparse clause 구조 구현
- 동일 입력군에 대한 성능 비교 수행

## 9. 미결정 항목

아래 항목은 다음 문서 또는 구현 단계에서 구체화가 필요하다.

- TPTP subset에서 `include(...)`를 언제 지원할지
- `$true`, `$false`를 clause 내부에서 어떻게 정규화할지
- tautological clause와 duplicate clause의 정규화 정책
- benchmark 결과 저장 형식
- 랜덤 생성 입력과 TPTP 실문제 입력의 혼합 비율

## 10. 참고 문서

- TPTP Language: <https://tptp.org/UserDocs/TPTPLanguage/TPTPLanguage.shtml>
- TPTP Problem Library Manual: <https://tptp.org/UserDocs/ProblemLibraryManual/TPTPTR.shtml>
- TPTP Quick Guide: <https://tptp.org/UserDocs/QuickGuide/>
