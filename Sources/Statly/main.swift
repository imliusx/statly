// SPM 构建时逻辑在 StatlyKit 库模块；Xcode App target 把全部源码编进同一模块，无需导入
#if canImport(StatlyKit)
import StatlyKit
#endif

// 进程入口必然在主线程上执行
MainActor.assumeIsolated {
    StatlyApp.run()
}
