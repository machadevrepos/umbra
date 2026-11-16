import com.android.build.api.variant.LibraryAndroidComponentsExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    if (name == "reactive_ble_mobile") {
        plugins.withId("com.android.library") {
            extensions.configure<LibraryAndroidComponentsExtension> {
                // The pinned BLE plugin targets API 33, below its resolved AndroidX requirements.
                finalizeDsl { dsl -> dsl.compileSdk = 36 }
            }
        }
    }

    // Kotlin's incremental cache cannot relativize plugin sources on C: against this D: checkout.
    if (System.getProperty("os.name").startsWith("Windows")) {
        extensions.extraProperties["kotlin.incremental"] = "false"
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
