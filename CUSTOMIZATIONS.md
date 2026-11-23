# 내 커스텀 목록 (공식 업데이트 때마다 이 순서로 다시 확인)

공식 패치(예: 1116) + 이 폴더(cocV26)를 Claude에게 주고 "커스텀 목록대로 다시 적용해줘"라고 하면 됩니다.

## 1. 한글화 (koName)
- 표: `clash_widgets/Models.swift` 의 `KoreanNames.table` (영어 이름 -> 한글). 키가 공식 이름과 정확히 같아야 함.
- 적용 위치: `Text(koName(UpgradePresentationCatalog.shared.displayName(for: upgrade)))` 형태.
  BuilderRow.swift, ClashDashWidget.swift, ProgressView, BoostView, EquipmentTabView, ProfileDetailView, NotificationManager 등.
- 주의: `displayName(for:)` 함수 자체를 감싸면 안 됨 (아이콘 파일명 조회에도 쓰임).
- 업데이트 때 필요한 것: 새로 추가/이름이 바뀐 건물, 마법, 영웅, 장비, 펫, 분대의 영어 이름과 한글 이름.

## 2. 위젯 탭 새로고침
- PlayerAccount.widgetTapRefresh (프로필 설정 토글, DataService / DataService+Persistence / ProfileDetailView)
- 위젯: `widgetTapAction(refresh:)`, `RefreshWidgetIntent` (ClashDashWidget.swift). 켜면 탭 시 앱을 열지 않고 갱신.
- 공식 멀티계정 위젯도 같은 방식 (표시 중 계정 중 하나라도 켜져 있으면 새로고침).

## 3. 추가 위젯
- Combined 4종, Dual Profile 2종 (ClashDashWidget.swift 파일 끝, ClashDashWidgetBundle.swift 에 등록)

## 4. 기타 (파일 하나짜리라 충돌 적음)
- 앱 아이콘 배지 / 취침 시간 관련 수정 (SettingsView, BoostView, ContentView, DashboardView 등)
- 빌드: `.github/workflows/ios-build.yml` (GitHub Actions), SideStore 설치용 `sidestore-fix.patch`

## 업데이트 시 Claude에게 알려줄 것
1. 새 공식 zip 과 이 CUSTOMIZATIONS.md 가 든 최신 zip
2. 게임 업데이트로 새로 생긴 항목의 영어 이름 -> 한글 이름 (모르면 "게임에서 확인해서 알려줄게"라고 해도 됨)
3. 앱 업데이트 내역(패치 노트)
4. 지난번과 달라진 동작이 있으면 그 증상 (예: 영어로 보이는 이름, 아이콘 안 뜸)

## 5. 남은 업그레이드 요약 화면 (cocV27 추가)
- 새 파일: `clash_widgets/ContentView/UpgradeSummaryView.swift` (project.pbxproj 에 등록돼 있음)
- 버튼: `UpgradeSummaryButton` 을 Home(DashboardView), Profile(ProfileDetailView), Progress(ProgressView), Equipment(EquipmentTabView) 툴바에서 `ProfileSwitcherMenu()` 바로 앞(왼쪽)에 추가
- 데이터: https://assets.clashk.ing/static_data.json 을 받아 캐시(24시간), 실패/누락 시 앱 내장 parsed_json_files 사용
- 골드패스 %는 비용과 시간 모두에 적용, 진행 중 항목은 % + 남은 시간 표시
- 섹션 순서: Heroes, Lab(Troops, Spells, Dark Troops, Sieges, Squads), Pets, Army, Defenses, Guardians, Resources, Crafted Def.
- 공식 업데이트 후 확인: `ProgressCatalog`(항목/최대 레벨), `CoCExport`, `DataService.cachedTownHallLevels` 이름이 바뀌지 않았는지
- 화면 제목은 "Upgrades". 왼쪽 위 닫기 버튼 옆의 편집 버튼(Edit Upgrades Cards)으로 섹션 on/off·순서·최대 레벨 표시 on/off 설정 (AppStorage: upgradeSectionOrder, upgradeHiddenSections, upgradeShowMaxed)
- 상단 골드패스 줄: "골드패스 N% 적용 (남은시간)" (Profile 화면과 같은 초기화 시각 사용)
- (cocV29) Upgrades 화면: 같은 항목의 줄 배경을 검정/회색 반복 -> 한 가지 색(secondarySystemBackground)으로 통일, 이미지+레벨(x/y) 아래 여백 3 -> 9 (`UpgradeInstanceRow`)
- (cocV30) Upgrades 화면: Show Unbuilt Buildings 토글 삭제(미건설은 항상 표시) -> Show Max Level 토글로 교체. 합체 건물 규칙(`UpgradeSummaryBuilder.missingCount`): TH17+ 독수리 타워 미건설 숨김 / 리코셰 대포 1개당 대포 2 / 멀티 아처 타워 1개당 아처 타워 2 / 멀티 개조 타워 1개당 대포 1+아처 타워 1 / 로켓병 타워(Firecracker Tower) 1개당 아처 타워 1+투석기(Scattershot) 1 미건설 제외 / 슈퍼 마법사 타워 1개당 마법사 타워 2 미건설 제외. 이미지 위/아래 여백 9
- (cocV33) 프로필 버튼(`ProfileSwitcherMenu`): 탭하면 다음 프로필로 순환 전환, 꾹 누르면 기존 프로필 목록 메뉴. 아이콘 색은 현재 프로필 순서 기준 1번 금색/2번 은색/3번 이후 구리색 (다크·라이트 모드별 색 따로 지정)
- (cocV34) 프로필 버튼 색: 1번 금색(#FFD23F) / 2번 회청색 은색(#A9B2BF) / 3번 이후 구리색(#E58A4A) (다크 모드 기준, 라이트 모드는 더 진한 색). 홈 탭 업그레이드 줄(`BuilderRow`): 왼쪽 묶음(이미지·Lv·기간) 폭을 68로 고정해 진행 막대 시작점 통일 (위젯은 미적용)
- (cocV35) 이미지 용량 정리: 마을 회관 th13·th18(4096px, 합 23MB)과 펫 sneezy(1200px)의 투명 여백을 잘라내고 비율 유지한 채 축소 (th13/th18 긴 변 640px, sneezy 300px). 다른 이미지(배경·changelog·AppIcon 등)는 그대로
