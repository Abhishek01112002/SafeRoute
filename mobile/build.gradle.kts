plugins {
    kotlin("jvm") version "2.3.0"
    application
}

group = "com.saferoute.app"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

dependencies {
    testImplementation(kotlin("test"))
}

kotlin {
    jvmToolchain(23)
}

application {
    mainClass.set("com.saferoute.app.MainKt")
}

tasks.test {
    useJUnitPlatform()
}