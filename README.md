# Hello World · Docker, Kubernetes, AWS

Flask-застосунок із Nginx, інфраструктурою Terraform і автоматичним deployment через GitHub Actions. AWS-регіон: **Frankfurt (`eu-central-1`)**.

**[Відкрити сайт](http://3.64.215.156)** · [Перевірка здоров’я](http://3.64.215.156/healthz) · [CI/CD](https://github.com/yuspax/test-task/actions/workflows/ci-cd.yml)

`/` повертає `Hello, World!`, `/healthz` — `{"status":"ok"}`. Це тестове середовище: одна EC2, HTTP без TLS. Публічна IP може змінитися після stop/start сервера.

## Як усе працює

```text
Локально: браузер → localhost:8080 → Nginx → Gunicorn / Flask
AWS:      браузер → EC2:80 → Traefik (Ingress) → Nginx → Gunicorn / Flask
CI/CD:    git push → тести → Docker build → ECR → SSM → K3s deployment
```

| Файли | Призначення |
| --- | --- |
| [app.py](app.py), [requirements.txt](requirements.txt) | Python-застосунок і зафіксовані залежності. Gunicorn запускає Flask на порту 8000. |
| [Dockerfile](Dockerfile) | Образ Python-застосунку. |
| [nginx/](nginx/) | Окремий образ Nginx: приймає HTTP на 8080 та проксіює до Python. Entrypoint підставляє адресу backend у конфігурацію. |
| [compose.yaml](compose.yaml) | Локально збирає та запускає обидва контейнери, налаштовує мережу й healthchecks. |
| [k8s/app.yaml](k8s/app.yaml) | Kubernetes: namespace, Deployment, Service та Ingress. |
| [infra/bootstrap/](infra/bootstrap/) | Одноразово створює приватний S3 bucket для Terraform state із шифруванням і versioning. |
| [infra/main/](infra/main/) | Створює мережу, EC2, ECR, IAM roles та GitHub OIDC provider. |
| [user-data.sh.tftpl](infra/main/templates/user-data.sh.tftpl) | Перший запуск EC2: встановлює K3s, AWS CLI, налаштовує SSM, шифрування Secrets та оновлення ECR token. |
| [.github/workflows/ci-cd.yml](.github/workflows/ci-cd.yml) | Автоматичні перевірки, публікація образів і розгортання. |
| [tests/test_app.py](tests/test_app.py) | Перевіряє привітання, health endpoint і відповідь 404. |

**Чому два Dockerfile?** Python і Nginx — окремі програми: кожна має власний образ, процес і логи. Compose запускає їх як два сервіси; у Kubernetes вони працюють разом в одному **pod**. Локально Nginx знаходить Python за `app:8000`, у спільній мережі pod — за `127.0.0.1:8000`.

**Для чого Kubernetes?** K3s — компактна збірка Kubernetes на нашій EC2. Deployment підтримує один pod із двома контейнерами, перевіряє готовність і виконує rolling update: новий pod має стати готовим до видалення старого. Service знаходить pod за labels, Ingress задає маршрут `/`, а Traefik приймає зовнішні запити. Readiness визначає готовність до трафіку, liveness перезапускає несправний контейнер. Один вузол не забезпечує доступності при відмові самої EC2.

**Для чого bootstrap?** Terraform зберігає відповідність між кодом і ресурсами у state. Спочатку `infra/bootstrap` створює S3 для основного state; його власний state залишається локальним. Окремо user-data виконує початкове налаштування сервера через cloud-init. Terraform керує інфраструктурою, Kubernetes — запущеними контейнерами.

## Локальний запуск

Потрібні Git, Python 3.13+, Docker Engine / Desktop із Compose v2.20+. Запустіть Docker Desktop, потім:

```bash
git clone https://github.com/yuspax/test-task.git
cd test-task
bash scripts/up.sh
```

Відкрийте **http://localhost:8080**. Для private-репозиторію потрібен доступ GitHub; якщо проєкт уже є на ноутбуці, використовуйте наявну папку. Після змін повторіть `bash scripts/up.sh` для перебудови.

```bash
docker compose ps
docker compose logs --tail=100 app nginx
python3 scripts/smoke.py
docker compose down
```

Якщо порт зайнятий: `HTTP_PORT=8081 bash scripts/up.sh`. Тести без Docker:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m unittest discover -s tests -v
```

## Розгортання у власному AWS

Команди нижче — **для нового середовища**, з кореня репозиторію. Для наявного сайту достатньо push у `main`. Потрібні AWS CLI 2.32+, Terraform 1.10+, Python, GitHub CLI та права створення AWS-ресурсів, включно з IAM.

**1. Доступ і параметри.** Репозиторій має бути у вашому GitHub. Авторизуйтеся:

```bash
aws login --profile terraform --region eu-central-1
aws sts get-caller-identity --profile terraform
gh auth login
```

Якщо `.tfvars` ще немає, скопіюйте шаблони; наявні файли з параметрами збережіть:

```bash
cp infra/bootstrap/terraform.tfvars.example infra/bootstrap/terraform.tfvars
cp infra/main/terraform.tfvars.example infra/main/terraform.tfvars
```

В обох задайте свій `aws_account_id` і однаковий `project_name`. У main задайте `github_oidc_subject` саме свого репозиторію:

```bash
gh api repos/OWNER/REPO/actions/oidc/customization/sub
```

До отриманого `sub_claim_prefix` додайте `:ref:refs/heads/main`. Поточний репозиторій використовує immutable IDs; subject іншого репозиторію не підійде. Стандартний subject старих репозиторіїв може мати вигляд `repo:OWNER/REPO:ref:refs/heads/main`. [Документація OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).

**2. Підготовка S3 для state.** Переглядайте кожний plan перед apply:

```bash
terraform -chdir=infra/bootstrap init
python3 scripts/terraform.py -chdir=infra/bootstrap plan -out=bootstrap.tfplan
python3 scripts/terraform.py -chdir=infra/bootstrap apply bootstrap.tfplan
python3 scripts/terraform.py -chdir=infra/bootstrap output -raw backend_config > infra/main/backend.tfbackend
```

Збережіть **`infra/bootstrap/terraform.tfstate`**: він потрібен для керування самим bucket. Основний state буде в S3.

**3. Створення сервера та доступів:**

```bash
python3 scripts/terraform.py -chdir=infra/main init -backend-config=backend.tfbackend
python3 scripts/terraform.py -chdir=infra/main plan -out=deploy.tfplan
python3 scripts/terraform.py -chdir=infra/main apply deploy.tfplan
python3 scripts/terraform.py -chdir=infra/main output
```

Якщо GitHub OIDC provider вже є в акаунті, узгодьте його імпорт замість повторного створення. Terraform може завершитися раніше за встановлення K3s. У **AWS Console → EC2 → Connect → Session Manager** перевірте:

```bash
sudo cloud-init status --wait
sudo test -f /var/lib/hello-world-bootstrap.done
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
```

Node має бути `Ready`, системні pod — готові. Застосунок з’явиться після першого deployment.

**4. GitHub Actions.** Отримайте налаштування:

```bash
python3 scripts/terraform.py -chdir=infra/main output -json github_actions_variables
```

Додайте їх у GitHub → Settings → Secrets and variables → Actions → **Variables**:

| Variable | Значення |
| --- | --- |
| `AWS_ROLE_ARN` | IAM role для workflow |
| `INSTANCE_ID` | EC2 для deployment через SSM |
| `SERVER_URL` | Публічна адреса для HTTP-перевірки |
| `ECR_REPOSITORY_PREFIX` | Префікс ECR, типово `hello-world` |

Зробіть push у `main` або **Actions → CI/CD → Run workflow** для `main`. Після успішних jobs сайт доступний за `website_url` із Terraform output. Після заміни EC2 / зміни IP оновіть Variables і посилання на сайт.

## CI/CD і скрипти

Кожний push і pull request запускає Flask-тести, збірку Compose, перевірку конфігурації Nginx та HTTP. Успішний `main` додатково отримує тимчасові AWS credentials через OIDC, публікує образи в ECR та розгортає їх через SSM. SSH-ключі не потрібні. Наприкінці перевіряються rollout і публічний сайт. Terraform автоматично у workflow не запускається.

| Скрипт | Що робить |
| --- | --- |
| `bash scripts/up.sh` | Перевіряє Docker, збирає й запускає Compose, чекає healthchecks, перевіряє HTTP. |
| `python3 scripts/smoke.py [URL]` | Перевіряє точні відповіді `/` і `/healthz`; типова адреса — `http://localhost:8080`. |
| `bash scripts/build.sh FULL_COMMIT_SHA` | Авторизується в ECR, збирає два `linux/amd64` образи та публікує з тегом commit SHA. Наявний immutable tag використовує повторно. |
| `python3 scripts/deploy.py FULL_COMMIT_SHA` | Підставляє образи у YAML, передає його через SSM, виконує `kubectl apply`, чекає rollout. При невдалому rollout пробує повернути попередню revision. |
| `python3 scripts/terraform.py ...` | Передає локальні AWS credentials Terraform через environment, без запису ключів у файли. |

Deployment виконується по одному; швидкі push можуть замінити старіший pending deployment. Помилка фінального HTTP-тесту сама не викликає rollback. На першому deployment попередньої revision ще немає.

Звичайний release: змініть код → перевірте тести → commit → `git push origin main`. При зміні привітання оновіть очікування в `tests/test_app.py` і `scripts/smoke.py`. Для ручного build / deployment із ноутбука потрібні Docker, AWS login і створена інфраструктура:

```bash
export AWS_PROFILE=terraform AWS_REGION=eu-central-1
export INSTANCE_ID="$(python3 scripts/terraform.py -chdir=infra/main output -raw instance_id)"
bash scripts/build.sh "$(git rev-parse HEAD)"
python3 scripts/deploy.py "$(git rev-parse HEAD)"
python3 scripts/smoke.py "$(python3 scripts/terraform.py -chdir=infra/main output -raw website_url)"
```

Для свого нестандартного `project_name` також задайте `ECR_REPOSITORY_PREFIX`. Зміни для ручного build мають бути закомічені, щоб SHA відповідав коду.

## Обслуговування і безпека

Локальні логи: `docker compose logs --tail=100`. Серверні команди виконуйте **на EC2 через Session Manager**:

```bash
sudo k3s kubectl -n hello-world get deployments,pods,services,ingresses
sudo k3s kubectl -n hello-world logs deployment/hello-world -c app --tail=100
sudo k3s kubectl -n hello-world logs deployment/hello-world -c nginx --tail=100
sudo k3s kubectl -n hello-world describe pods
sudo tail -n 100 /var/log/hello-world-bootstrap.log
sudo journalctl -u ecr-refresh.service --no-pager -n 30
```

При `ImagePullBackOff` перевірте образ у ECR і `ecr-refresh.service`; якщо сайт недоступний — поточну IP, порт 80, Traefik і стан pod. Для змін інфраструктури повторіть main `plan` / `apply`: зміна AMI або user-data може замінити EC2. Логи контейнерів ротуються; tagged образи в ECR періодично прибирайте, зберігаючи поточні та потрібні для rollback.

AWS keys не зберігаються в репозиторії чи GitHub Variables. OIDC trust policy дозволяє доступ лише `main` конкретного репозиторію; клон або fork цього доступу не отримує. Можливість змінювати оригінальний `main` дає змогу запускати deployment із правами CI role. `.gitignore` виключає state, `.tfvars`, плани та ключі. SSH і Kubernetes API закриті з інтернету. ECR token у Kubernetes Secret шифрується K3s та оновлюється кожні 4 години через EC2 role.

## Зупинка і видалення

- Локально: `docker compose down`. AWS продовжує працювати й тарифікуватися.
- Для видалення AWS дочекайтеся deployment і вимкніть workflow. Спорожніть **два ECR-репозиторії проєкту**, потім перегляньте й застосуйте план:

```bash
python3 scripts/terraform.py -chdir=infra/main plan -destroy -out=destroy.tfplan
python3 scripts/terraform.py -chdir=infra/main apply destroy.tfplan
```

S3 для state залишається. Для остаточного видалення bucket збережіть потрібні state, спорожніть його разом з усіма versions / delete markers, приберіть `prevent_destroy` з bootstrap та виконайте:

```bash
python3 scripts/terraform.py -chdir=infra/bootstrap plan -destroy -out=destroy-bootstrap.tfplan
python3 scripts/terraform.py -chdir=infra/bootstrap apply destroy-bootstrap.tfplan
```

Для видалення локальної AWS-сесії: `aws logout --profile terraform`; за потреби приберіть лише `[profile terraform]` з `~/.aws/config`. Це не видаляє AWS-ресурси.
