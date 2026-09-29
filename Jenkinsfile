#!/usr/bin/env groovy
// ============================================================
// mall 持续交付流水线（Jenkins Declarative Pipeline）
//   运行位置：ops 上的 Jenkins（控制器与执行器同一台，实验环境）
//   任务配置：New Item → Pipeline → Pipeline script from SCM
//             SCM: https://github.com/<你>/mall-deploy.git（分支 main/master）
//             Script Path: jenkins/Jenkinsfile
//   Jenkins 侧前置（8.5 节）：
//     ① 全局环境变量 GIT_BASE_URL（例：https://github.com/lujinlei6）
//     ② 凭据 ID harbor-cred（Harbor 机器人账号，library 项目 push 权限）
//     ③ /var/lib/jenkins/.kube/config（角色 jenkins 已下发）
// ============================================================

pipeline {
  agent any

  triggers {
    // 每 5 分钟唤醒一次做"变更检测"（机制与取舍见文档 8.6.1）
    cron('H/5 * * * *')
  }

  options {
    timestamps()                                     // 日志时间戳（timestamper）
    ansiColor('xterm')                               // 彩色控制台（ansicolor）
    timeout(time: 45, unit: 'MINUTES')               // 兜底超时，避免卡死占住执行器
    disableConcurrentBuilds()                        // 串行：不允许两次构建同时 helm upgrade
    buildDiscarder(logRotator(numToKeepStr: '10'))   // 只保留最近 10 次构建（磁盘治理）
  }

  environment {
    REGISTRY_HOST = 'harbor.lab'                     // Harbor VIP（第 6 章）
    REGISTRY      = 'harbor.lab/library'             // 镜像仓库前缀（= Dockerfile 的 BASE_REGISTRY）
    NAMESPACE     = 'kube-mall'
    RELEASE       = 'mall'
  }

  stages {

    stage('Checkout two repos') {
      steps {
        script {
          if (!env.GIT_BASE_URL?.trim()) {
            error('未配置全局环境变量 GIT_BASE_URL —— 见文档 8.5.2')
          }
        }
        // 主 SCM（mall-deploy）已由 Jenkins 检出到工作区根目录；源码仓库只有一个：
        // mall4j 前后端同仓（后端 yami-shop-admin + 前端 front-end/mall4v）
        dir('src-mall4j') { git url: "${env.GIT_BASE_URL}/mall4j.git", branch: 'lab' }

        script {
          // ⚠️ 下面这些变量故意不加 def：不加 def 才是脚本级变量，后面的 stage 才读得到
          currentShas = sh(
            script: 'git rev-parse HEAD; git -C src-mall4j rev-parse HEAD',
            returnStdout: true).trim()
          lastShas = fileExists('.last-built-shas') ? readFile('.last-built-shas').trim() : ''
          // 定时触发 → 先做变更检测；人工"立即构建" → 总是完整执行
          autoTriggered = ['TIMERTRIGGER', 'SCMTRIGGER'].contains(env.BUILD_CAUSE)
          needsBuild    = !autoTriggered || (currentShas != lastShas)

          // 镜像 tag：构建号（部署/回滚用）+ git 短 SHA（溯源用），见 9.4
          // 前后端同仓 → 共用一个 GIT_TAG
          env.GIT_TAG = "git-${sh(script: 'git -C src-mall4j rev-parse --short=7 HEAD', returnStdout: true).trim()}"
          currentBuild.description = "mall4j:${env.BUILD_NUMBER}/${env.GIT_TAG}"
          echo "触发方式=${autoTriggered ? '定时' : '人工'}｜有变更=${currentShas != lastShas}｜本次需要构建=${needsBuild}"
        }

        sh 'java -version; git --version; docker version --format "docker-server {{.Server.Version}}"; kubectl version --client=true; helm version --short'
      }
    }

    stage('Build Backend Image') {
      when { expression { needsBuild } }
      steps {
        dir('src-mall4j') {
          sh """
            set -e
            DOCKER_BUILDKIT=1 docker build --progress=plain \
              -f docker/Dockerfile.admin \
              --build-arg BASE_REGISTRY=${REGISTRY} \
              -t ${REGISTRY}/mall4j-admin:${env.BUILD_NUMBER} \
              -t ${REGISTRY}/mall4j-admin:${env.GIT_TAG} .
          """
        }
      }
    }

    stage('Push Backend to Harbor') {
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
          """
        }
      }
    }

    stage('Build Frontend Image') {
      when { expression { needsBuild } }
      steps {
        // mall4v 与后端同仓，构建上下文同样是仓库根目录，只是换一个 Dockerfile
        dir('src-mall4j') {
          sh """
            set -e
            DOCKER_BUILDKIT=1 docker build --progress=plain \
              -f docker/Dockerfile.web \
              --build-arg BASE_REGISTRY=${REGISTRY} \
              -t ${REGISTRY}/mall4v:${env.BUILD_NUMBER} \
              -t ${REGISTRY}/mall4v:${env.GIT_TAG} .
          """
        }
      }
    }

    stage('Push Frontend to Harbor') {
      when { expression { needsBuild } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'harbor-cred',
                                          usernameVariable: 'HARBOR_USER',
                                          passwordVariable: 'HARBOR_PASS')]) {
          sh """
            set -e
            echo "\$HARBOR_PASS" | docker login ${REGISTRY_HOST} -u "\$HARBOR_USER" --password-stdin
            docker push ${REGISTRY}/mall4v:${env.BUILD_NUMBER}
            docker push ${REGISTRY}/mall4v:${env.GIT_TAG}
          """
        }
      }
    }

    stage('Helm Deploy') {
      when { expression { needsBuild } }
      steps {
        sh """
          set -e
          helm upgrade --install ${RELEASE} ./helm/mall \
            --namespace ${NAMESPACE} --create-namespace \
            --set backend.image.tag=${env.BUILD_NUMBER} \
            --set frontend.image.tag=${env.BUILD_NUMBER} \
            --wait --timeout 5m
          helm -n ${NAMESPACE} history ${RELEASE} | tail -n 5
        """
      }
    }

    stage('Verify Rollout') {
      when { expression { needsBuild } }
      steps {
        sh """
          set -e
          kubectl -n ${NAMESPACE} rollout status deploy/mall4j-admin --timeout=300s
          kubectl -n ${NAMESPACE} rollout status deploy/mall4v       --timeout=300s
          image=\$(kubectl -n ${NAMESPACE} get deploy mall4j-admin -o jsonpath='{.spec.template.spec.containers[0].image}')
          echo "后端当前镜像：\$image"
          echo "\$image" | grep -q ':${env.BUILD_NUMBER}\$' \
            || { echo "镜像 tag 与本次构建号不一致，判定失败"; exit 1; }
          kubectl -n ${NAMESPACE} get pods -o wide
        """
      }
    }

    stage('Smoke Test') {
      when { expression { needsBuild } }
      steps {
        // mall4j 的登录要先过人机验证码、密码又是前端加密传输，命令行无法伪造完整登录链路；
        // 冒烟改为三条断言：前端 200 + 验证码接口成功码（应用+Redis 活体）+ 登录路由可达（参数校验失败码）
        sh """
          set -e
          echo '--- 前端页面 ---'
          curl -fsS -o /dev/null -w 'HTTP %{http_code}\\n' \
            --retry 5 --retry-delay 3 --retry-all-errors http://mall.lab/
          echo '--- 后端：验证码接口（成功码 00000 → 应用 + Redis 整条链路通）---'
          resp=\$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors \
            -X POST http://mall.lab/api/captcha/get \
            -H 'Content-Type: application/json' \
            -d '{"captchaType":"blockPuzzle"}')
          echo "\$resp" | head -c 200; echo
          echo "\$resp" | grep -q '"code":"00000"' || { echo '验证码接口未返回成功码，冒烟失败'; exit 1; }
          echo '--- 后端：登录接口可达性（空 body 触发参数校验失败码 A00014）---'
          resp2=\$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors \
            -X POST http://mall.lab/api/adminLogin \
            -H 'Content-Type: application/json' \
            -d '{}')
          echo "\$resp2" | head -c 200; echo
          echo "\$resp2" | grep -q '"code":"A00014"' || { echo '登录接口未返回预期的参数校验失败码，冒烟失败'; exit 1; }
          echo '冒烟通过：前端 200 + 验证码服务健康 + 登录路由可达'
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
      echo "构建成功：mall4j-admin:${env.BUILD_NUMBER} / mall4v:${env.BUILD_NUMBER} 已上线（mall.lab）"
    }
    unsuccessful {
      echo '构建未成功：按控制台从上往下第一个红色的 Stage 排查，排错表见文档 8.8'
    }
  }
}
