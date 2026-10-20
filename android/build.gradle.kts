import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

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
// screen_protector 1.5.3 assumes AGP 9 always enables built-in Kotlin.
// Flutter explicitly disables it in this project, so compile that plugin with KGP.
subprojects {
    if (name == "screen_protector") {
        pluginManager.withPlugin("com.android.library") {
            if (findProperty("android.builtInKotlin")?.toString() == "false") {
                pluginManager.apply("org.jetbrains.kotlin.android")
                extensions.configure<KotlinAndroidProjectExtension> {
                    compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
