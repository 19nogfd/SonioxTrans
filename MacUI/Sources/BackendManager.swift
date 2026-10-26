import Foundation
import Combine

class BackendManager {
    static let shared = BackendManager()
    
    private var process: Process?
    private var isRunning = false
    
    func start() {
        if isRunning { return }
        
        DispatchQueue.global(qos: .background).async {
            self.runProcess()
        }
        
        // Wait a second for python server to boot
        Thread.sleep(forTimeInterval: 1.0)
        WebSocketManager.shared.connect()
    }
    
    private func runProcess() {
        let task = Process()
        
        // 尝试寻找被打包在 App 内部的后端引擎二进制文件
        guard let serverURL = Bundle.main.url(forResource: "server", withExtension: nil, subdirectory: "python_backend") else {
            print("Error: 找不到打包好的后端引擎！确保你是在打包模式下运行的该 App。")
            return
        }
        
        // 将执行路径设在内部 Resources 目录下，便于读取同目录层的 models
        if let resourcesURL = Bundle.main.resourceURL {
            task.currentDirectoryPath = resourcesURL.path
        }
        
        task.launchPath = serverURL.path
        // 不再需要任何参数，因为 server 是被 PyInstaller 打包好的单个独立可执行文件
        task.arguments = []
        
        // Pipe outputs to nullDevice so standard print logs don't fill the memory and block the python process!
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        
        self.process = task
        
        do {
            try task.run()
            self.isRunning = true
            print("Backend Python Process Started with PID \(task.processIdentifier)")
            task.waitUntilExit()
        } catch {
            print("Failed to start backend: \(error)")
        }
        self.isRunning = false
    }
    
    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
        WebSocketManager.shared.disconnect()
    }
}
