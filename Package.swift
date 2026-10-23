// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ekko",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit",
                 from: "0.9.0"),
        // 2.21.2 = letzte Version, die mit WhisperKits swift-transformers-Pin
        // (<0.2) auflösbar ist. Qwen3 fehlt dort → eigener Port
        // (Qwen3Modell.swift), registriert in QwenCleanup.
        .package(url: "https://github.com/ml-explore/mlx-swift-examples",
                 exact: "2.21.2"),
        // mlx-swift auf die zu 2.21.2 zeitgenössische Linie pinnen —
        // 0.30+ bricht deren Quantizable-API.
        .package(url: "https://github.com/ml-explore/mlx-swift",
                 exact: "0.21.3"),
    ],
    targets: [
        .executableTarget(
            name: "Ekko",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
            ],
            path: "Sources/Ekko"
        ),
        .testTarget(
            name: "EkkoTests",
            dependencies: ["Ekko"],
            path: "Tests/EkkoTests"
        )
    ]
)
