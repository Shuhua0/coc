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
- 화면 제목은 "Upgrades". 왼쪽 위 닫기 버튼 옆의 편집 버튼(Edit Upgrades Cards)으로 섹션 on/off·순서·미건설 건물 표시 on/off 설정 (AppStorage: upgradeSectionOrder, upgradeHiddenSections, upgradeShowUnbuilt)
- 상단 골드패스 줄: "골드패스 N% 적용 (남은시간)" (Profile 화면과 같은 초기화 시각 사용)
