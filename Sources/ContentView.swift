import SwiftUI
import UserNotifications

struct ContentView: View {
    @StateObject var timerManager = TimerManager.shared
    @State var inputMinutes: String = "1"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("미니 타이머 & 위젯")
                .font(.largeTitle)
                .bold()
            
            Text("\(timerManager.remainingSeconds)초 남음")
                .font(.system(size: 48, weight: .bold))
                .monospacedDigit()
            
            TextField("분 입력", text: $inputMinutes)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)
                .frame(width: 150)
            
            Button(action: {
                if let mins = Int(inputMinutes) {
                    timerManager.startTimer(seconds: mins * 60)
                }
            }) {
                Text("타이머 시작")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
        .onAppear {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }
}