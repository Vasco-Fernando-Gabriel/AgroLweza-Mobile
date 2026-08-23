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

// Alguns plugins (ex: tflite_flutter) nao definem sourceCompatibility/jvmTarget
// proprios e acabam herdando a versao do JDK do sistema (25), gerando
// "Inconsistent JVM Target Compatibility" contra o Java 1.8 default deles.
// Forca Java/Kotlin 17 em todos os subprojetos para alinhar com o app.
// Precisa ser registado ANTES do evaluationDependsOn(":app") abaixo, senao
// o :app ja terminou de avaliar quando tentamos anexar o afterEvaluate.
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.apply {
            // tflite_flutter fica preso ao compileSdk 31, mais baixo do que
            // varias das suas proprias dependencias AndroidX exigem. Alinha
            // com o compileSdk do :app para resolver.
            compileSdkVersion(36)
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
