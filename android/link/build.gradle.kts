// Pure Kotlin (no Android) twin of ios/Shared/BCLink.swift and firmware components/bc_core/bc_link.c.
plugins { id("org.jetbrains.kotlin.jvm") }
kotlin { jvmToolchain(17) }
dependencies { testImplementation("junit:junit:4.13.2") }
