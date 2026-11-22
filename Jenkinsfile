pipeline {
    environment {
        registry = "aarondvail/$BRANCH_NAME"
        registryCredential = 'DockerHub'
        dockerImage = ''
    }
    agent any
    //triggers {
    //    cron('0 2 * * 3')
    //}
    parameters {
        string(name: 'VERSION_NUMBER', defaultValue: '', description: 'Version to build. Leave empty to detect it automatically.')
    }
    stages {
        stage('Clone repository') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'Github', usernameVariable: 'Username', passwordVariable: 'Password')]) {
                    git 'https://github.com/aarondvail/Container-Dockerfiles.git'
                    sh "find . -name \"*.sh\" -exec chmod +x {} \\;"
                }
            }
        }
//    stage('SonarQube Analysis') {
//            def scannerHome = tool 'SonarScanner';
//        withSonarQubeEnv() {
//                  sh "${scannerHome}/bin/sonar-scanner"
//        }
//    }
        stage('Resolve version') {
            steps {
                script {
                    // The VERSION_NUMBER text box still wins when it's filled in
                    env.IMAGE_VERSION = (params.VERSION_NUMBER ?: '').trim()
                    if (!env.IMAGE_VERSION) {
                        switch (BRANCH_NAME.toLowerCase()) {
                            case 'minecraftbedrock':
                                // Latest release (not preview) from Mojang's download-links API.
                                // Browser user agent + HTTP/1.1: Microsoft's CDN stalls plain curl.
                                env.IMAGE_VERSION = sh(returnStdout: true, script: '''
                                    curl -fsS --http1.1 --max-time 60 \
                                         -A "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0" \
                                         -H "Accept-Language: en-US,en;q=0.9" \
                                         https://net-secondary.web.minecraft-services.net/api/v1.0/download/links \
                                      | grep -oE 'bin-linux/bedrock-server-[0-9.]+\\.zip' | head -1 \
                                      | sed -E 's/.*bedrock-server-([0-9.]+)\\.zip/\\1/' || true
                                ''').trim()
                                if (!env.IMAGE_VERSION) {
                                    error("Couldn't get the Bedrock version from Mojang - rerun with VERSION_NUMBER filled in")
                                }
                                break
                            case 'incrediblepbx':
                                // Year in the installer URL (IncrediblePBX2026.sh -> 2026)
                                env.IMAGE_VERSION = sh(returnStdout: true,
                                    script: "grep -oP 'IncrediblePBX\\K[0-9]{4}' incrediblepbx.dockerfile | head -1").trim()
                                break
                            case 'arkime':
                                // Newest vX.Y.Z release tag upstream
                                env.IMAGE_VERSION = sh(returnStdout: true, script: '''
                                    git ls-remote --tags --refs https://github.com/arkime/arkime.git 'v*' \
                                      | sed 's#.*/v##' | grep -E '^[0-9]+\\.[0-9]+\\.[0-9]+$' | sort -V | tail -1 || true
                                ''').trim()
                                break
                            case 'bitfocus-companion':
                                // Pinned in the dockerfile: ARG COMPANION_VERSION=v5.1.3
                                env.IMAGE_VERSION = sh(returnStdout: true,
                                    script: "grep -oP '^ARG COMPANION_VERSION=\\K[^\\s]+' bitfocus-companion.dockerfile | head -1").trim()
                                break
                            default:
                                // Optional convention for any other image: put
                                //   ARG IMAGE_VERSION=<version>
                                // in its dockerfile. Without it, the build number is used.
                                env.IMAGE_VERSION = sh(returnStdout: true,
                                    script: "grep -oP '^ARG IMAGE_VERSION=\\K[^\\s]+' ${BRANCH_NAME}.dockerfile 2>/dev/null | head -1").trim()
                        }
                    }
                    if (!env.IMAGE_VERSION) {
                        echo "No version found - falling back to the build number"
                        env.IMAGE_VERSION = "${BUILD_NUMBER}"
                    }
                    echo "Building version ${env.IMAGE_VERSION}"
                    currentBuild.displayName = "#${BUILD_NUMBER} ${env.IMAGE_VERSION}"
                }
            }
        }
    stage('Buildx image') {
            steps {
                script {
                    def dockerfile = "${BRANCH_NAME}.dockerfile"
                    // Docker Hub repository names must be lowercase (branch OpenTAKServer -> aarondvail/opentakserver)
                    def image = registry.toLowerCase()
                    echo "${image}:${env.IMAGE_VERSION} - ${dockerfile}"
                    if (dockerfile == "minecraftbedrock.dockerfile"){
                        // Download from Mojang and archive the zip in Nexus; fall back to Nexus
                        // if Mojang fails. The dockerfile COPYs bedrock-server-<version>.zip.
                        withCredentials([usernamePassword(credentialsId: 'Nexus_Integration', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                            sh '''
                                set -eu
                                V="$IMAGE_VERSION"
                                ZIP="bedrock-server-$V.zip"
                                MOJANG="https://www.minecraft.net/bedrockdedicatedserver/bin-linux/$ZIP"
                                NEXUS="http://172.16.248.11:8092/repository/minecraft/$V/$ZIP"
                                UA="Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"

                                if curl -fL --http1.1 --retry 3 --max-time 600 -A "$UA" \
                                        -H "Accept-Language: en-US,en;q=0.9" -o "$ZIP" "$MOJANG" \
                                   && unzip -tq "$ZIP"; then
                                    echo "Got $ZIP from Mojang - archiving to Nexus"
                                    curl -fsS -u "$NEXUS_USER:$NEXUS_PASS" --upload-file "$ZIP" "$NEXUS" \
                                        || echo "WARNING: Nexus upload failed (already there?) - continuing"
                                else
                                    echo "Mojang download failed - falling back to Nexus"
                                    rm -f "$ZIP"
                                    curl -fsS -u "$NEXUS_USER:$NEXUS_PASS" -o "$ZIP" "$NEXUS"
                                fi
                            '''
                        }
                    }
                    docker.withRegistry( '', registryCredential ) {
                        sh "docker run --rm --privileged docker/binfmt:820fdd95a9972a5308930a2bdfb8573dd4447ad3"
                        sh "docker buildx prune -f"
                        sh "docker buildx inspect mybuilder >/dev/null 2>&1 || docker buildx create --name mybuilder"
                        sh "docker buildx use mybuilder"
                        // One build, two tags: the version and latest
                        sh "docker buildx build --build-arg VERSION_NUMBER=${env.IMAGE_VERSION} --platform=linux/amd64 --tag ${image}:${env.IMAGE_VERSION} --tag ${image}:latest -f ${dockerfile} . --push"
                    }
                }
            }
        }
        stage('Cleaning up') {
            steps {
                //sh "docker rmi $registry:latest"
                deleteDir()
            }
        }
    }
}
