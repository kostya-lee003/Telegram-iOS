load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

filegroup(
    name = "LiquidGlassUIResources",
    srcs = [
        "LiquidGlassShaders.metal",
    ],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "LiquidGlassUI",
    module_name = "LiquidGlassUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
    ],
    # если у swift_library нет attr `data` в твоей версии rules_swift — просто убери этот блок
    data = [
        ":LiquidGlassUIResources",
    ],
    visibility = [
        "//visibility:public",
    ],
)
