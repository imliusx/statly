import StatlyKit

// 进程入口必然在主线程上执行
MainActor.assumeIsolated {
    StatlyApp.run()
}
