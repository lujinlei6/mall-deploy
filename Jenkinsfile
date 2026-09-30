#!/usr/bin/env groovy
// ============================================================
// mall 持续交付流水线（Jenkins Declarative Pipeline）
//   运行位置：ops 上的 Jenkins（控制器与执行器同一台，实验环境）
//   任务配置：New Item → Pipeline → Pipeline script from SCM
//             SCM: git@github.com:lujinlei6/mall-deploy.git（分支 main/master）
//             Script Path: Jenkinsfile
//   Jenkins 侧前置：
//     ① 全局环境变量 GIT_BASE_URL（例：https://github.com/lujinlei6）
//     ② 凭据 ID harbor-cred（Harbor 机器人账号，library 项目 push 权限）
//     ③ /var/lib/jenkins/.kube/config（角色 jenkins 已下发）
//   源码仓库 mall4j（含四个 Dockerfile）已推送到 GIT_BASE_URL/mall4j.git（默认分支 master）
//       yami-shop-admin/Dockerfile        后台后端（8085）
//       yami-shop-api/Dockerfile          商城后端（8086）
//       front-end/mall4v/Dockerfile       后台前端
//       front-end/mall4uni/Dockerfile     商城前端
//   每个 Dockerfile 自行完成多阶段构建，可直接 docker build。
// ============================================================

pipeline {
  agent any

  parameters {
    // 源码分支：可在 Jenkins 里改，不用动 Jenkinsfile
    string(name: 'SOURCE_BRANCH', defaultValue: 'master', description: 'mall4j 源码仓库分支')
  }

  options {
    timestamps()
    ansiColor('xterm')
    timeout(time: 60, unit: 'MINUTES')  // 多阶段构建 4 个镜像，放宽兜底超时
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '10'))
  }

  environment {
    REGISTRY_HOST = 'harbor.lab'
    REGISTRY      = 'harbor.lab/library'
    NAMESPACE     = 'kube-mall'
    RELEASE       = 'mall'
    ADMIN_HOST    = 'admin.mall.lab'   // 与 helm values.ingress.adminHost 保持一致
    MALL_HOST     = 'mall.lab'         // 与 helm values.ingress.mallHost 保持一致
  }

  stages {

    stage('Checkout source') {
      steps {
        script {
          if (!env.GIT_BASE_URL?.trim()) {
            error('未配置全局环境变量 GIT_BASE_URL —— 见文件头说明')
          }
        }
        // 拉取 mall4j 源码仓库（含四种 Dockerfile）
        dir('src-mall4j') {
          git url: "${env.GIT_BASE_URL}/mall4j.git", branch: params.SOURCE_BRANCH
        }

        script {
          currentShas = sh(
            script: 'git rev-parse HEAD; git -C src-mall4j rev-parse HEAD',
            returnStdout: true).trim()
          lastShas = fileExists('.last-built-shas') ? readFile('.last-built-shas').trim() : ''
          autoTriggered = ['TIMERTRIGGER', 'SCMTRIGGER'].contains(env.BUILD_CAUSE)
          needsBuild    = !autoTriggered || (currentShas != lastShas)

          env.GIT_TAG = "git-${sh(script: 'git -C src-mall4j rev-parse --short=7 HEAD', returnStdout: true).trim()}"
          currentBuild.description = "mall4j:${env.BUILD_NUMBER}/${env.GIT_TAG}"
          echo "触发方式=${autoTriggered ? '定时' : '人工'}｜源码分支=${params.SOURCE_BRANCH}｜有变更=${currentShas != lastShas}｜本次需要构建=${needsBuild}"
        }

        sh 'java -version; git --version; docker version --format "docker-server {{.Server.Version}}"; kubectl version --client=true; helm version --short'
      }
    }

    // ---------- 后端 mall4j-admin（后台）----------
    stage('Build backend-admin') {
      when { expression { needsBuild } }
      steps {
        dir('src-mall4j') {
          sh """
            set -e
            DOCKER_BUILDKIT=1 docker build --progress=plain \
              -f yami-shop-admin/Dockerfile \
              -t ${REGISTRY}/mall4j-admin:${env.BUILD_NUMBER} \
              -t ${REGISTRY}/mall4j-admin:${env.GIT_TAG} .
          """
        }
      }
    }

    // ---------- 后端 mall4j-api（商城）----------
    stage('Build backend-api') {
      when { expression { needsBuild } }
      steps {
        dir('src-mall4j') {
          sh """
            set -e
            DOCKER_BUILDKIT=1 docker build --progress=plain \
              -f yami-shop-api/Dockerfile \
              -t ${REGISTRY}/mall4j-api:${env.BUILD_NUMBER} \
              -t ${REGISTRY}/mall4j-api:${env.GIT_TAG} .
          """
        }
      }
    }

    // ---------- 前端 mall4v（后台页面）----------
    stage('Build frontend-admin (mall4v)') {
      when { expression { needsBuild } }
      steps {
        dir('src-mall4j') {
          sh """
            set -e
            DOCKER_BUILDKIT=1 docker build --progress=plain \
              -t ${REGISTRY}/mall4v:${env.BUILD_NUMBER} \
              -t ${REGISTRY}/mall4v:${env.GIT_TAG} \
              front-end/mall4v
          """
        }
      }
    }

    // ---------- 前端 mall4uni（商城页面）----------
    stage('Build frontend-mall (mall4uni)') {
      when { expression { needsBuild } }
      steps {
        dir('src-mall4j') {
          sh """
            set -e
            DOCKER_BUILDKIT=1 docker build --progress=plain \
              -t ${REGISTRY}/mall4uni:${env.BUILD_NUMBER} \
              -t ${REGISTRY}/mall4uni:${env.GIT_TAG} \
              front-end/mall4uni
          """
        }
      }
    }

    // ---------- 推送四个镜像到 Harbor ----------
    stage('Push all images to Harbor') {
      when { expression { needsBuild } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'harbor-cred',
                                          usernameVariable: 'HARBOR_USER',
                                          passwordVariable: 'HARBOR_PASS')]) {
          sh """
            set -e
            echo "\$HARBOR_PASS" | docker login ${REGISTRY_HOST} -u "\$HARBOR_USER" --password-stdin
            docker push ${REGISTRY}/mall4j-admin:${env.BUILD_NUMBER}
            docker push ${REGISTRY}/mall4j-admin:${env.GIT_TAG}
            docker push ${REGISTRY}/mall4j-api:${env.BUILD_NUMBER}
            docker push ${REGISTRY}/mall4j-api:${env.GIT_TAG}
            docker push ${REGISTRY}/mall4v:${env.BUILD_NUMBER}
            docker push ${REGISTRY}/mall4v:${env.GIT_TAG}
            docker push ${REGISTRY}/mall4uni:${env.BUILD_NUMBER}
            docker push ${REGISTRY}/mall4uni:${env.GIT_TAG}
          """
        }
      }
    }

    // ---------- Helm 部署四个服务 ----------
    stage('Helm Deploy') {
      when { expression { needsBuild } }
      steps {
        sh """
          set -e
          helm upgrade --install ${RELEASE} ./helm/mall \
            --namespace ${NAMESPACE} --create-namespace \
            --set backendAdmin.image.tag=${env.BUILD_NUMBER} \
            --set backendApi.image.tag=${env.BUILD_NUMBER} \
            --set frontendAdmin.image.tag=${env.BUILD_NUMBER} \
            --set frontendMall.image.tag=${env.BUILD_NUMBER} \
            --wait --timeout 5m
          helm -n ${NAMESPACE} history ${RELEASE} | tail -n 5
        """
      }
    }

    // ---------- 校验四个 Deployment 滚动完成且镜像 tag 正确 ----------
    stage('Verify Rollout') {
      when { expression { needsBuild } }
      steps {
        sh """
          set -e
          for dep in mall4j-admin mall4j-api mall4v mall4uni; do
            kubectl -n ${NAMESPACE} rollout status deploy/\$dep --timeout=300s
            image=\$(kubectl -n ${NAMESPACE} get deploy \$dep -o jsonpath='{.spec.template.spec.containers[0].image}')
            echo "\$dep 当前镜像：\$image"
            echo "\$image" | grep -q ':${env.BUILD_NUMBER}\$' \
              || { echo "\$dep 镜像 tag 与本次构建号不一致，判定失败"; exit 1; }
          done
          kubectl -n ${NAMESPACE} get pods -o wide
        """
      }
    }

    // ---------- 冒烟测试 ----------
    stage('Smoke Test') {
      when { expression { needsBuild } }
      steps {
        sh """
          set -e
          echo '--- 后台页面 (admin.mall.lab) ---'
          curl -fsS -o /dev/null -w 'HTTP %{http_code}\\n' \
            --retry 5 --retry-delay 3 --retry-all-errors http://${env.ADMIN_HOST}/
          echo '--- 后台后端：验证码接口（成功码 00000 → 应用 + Redis 整条链路通）---'
          resp=\$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors \
            -X POST http://${env.ADMIN_HOST}/api/captcha/get \
            -H 'Content-Type: application/json' \
            -d '{"captchaType":"blockPuzzle"}')
          echo "\$resp" | grep -q '"code":"00000"' || { echo '验证码接口未返回成功码，冒烟失败'; exit 1; }
          echo '--- 后台后端：登录接口可达性（空 body 触发参数校验失败码 A00014）---'
          resp2=\$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors \
            -X POST http://${env.ADMIN_HOST}/api/adminLogin \
            -H 'Content-Type: application/json' \
            -d '{}')
          echo "\$resp2" | grep -q '"code":"A00014"' || { echo '登录接口未返回预期校验失败码，冒烟失败'; exit 1; }
          echo '--- 商城页面 (mall.lab) ---'
          curl -fsS -o /dev/null -w 'HTTP %{http_code}\\n' \
            --retry 5 --retry-delay 3 --retry-all-errors http://${env.MALL_HOST}/
          echo '冒烟通过：两个前端页面 200 + 后台验证码服务健康 + 登录路由可达'
        """
        script {
          // 只有走完冒烟测试才记录基线 —— "上次成功构建的 SHA"
          writeFile file: '.last-built-shas', text: currentShas + '\n'
        }
      }
    }
  }

  post {
    success {
      echo "构建成功：mall4j-admin/api + mall4v/mall4uni 已上线（admin.mall.lab / mall.lab）"
    }
    unsuccessful {
      echo '构建未成功：按控制台从上往下第一个红色的 Stage 排查'
    }
  }
}