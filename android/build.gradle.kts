allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // Los plugins de Flutter declaran cada uno su propio AGP en su buildscript
    // (app_links pide 8.6.1, otros 8.5.0, 8.1.2, 8.13.1...). Eso obliga a bajar
    // un juego completo de herramientas Android por version. Forzamos el 8.11.1
    // que ya usa :app para resolver todo desde la cache local.
    buildscript {
        configurations.configureEach {
            resolutionStrategy.eachDependency {
                if (requested.group == "com.android.tools.build" && requested.name == "gradle") {
                    useVersion("8.11.1")
                }
            }
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
