# Drakkar Lite Setup Guide for DigitalOcean for Nordheim Online v.1

**Prepared for:** Nordheim Online  
**Prepared by:** Chuck Talk  
**Version:** 1.0 September 19, 2026

## About this guide

This guide walks you through setting up Drakkar Lite, Nordheim Online's contact-management web app, on DigitalOcean. You do not need to be a Kubernetes expert. If you can copy a command, paste it into a terminal, and press Enter, you can finish this guide.

Every step is laid out the same way:

- **What you're doing:** The task in plain words.
- **Why:** The reason it matters so you're never typing something you don't understand.
- **Do this:** The exact commands. Copy them one block at a time.
- **Check it worked:** What you should see before moving on. **Don't move on until the check passes.** Most problems come from skipping a check.

### What you'll have at the end

- The Drakkar Lite app running at **https://drakkar.nordheim.online**, with a padlock in the browser.
- A setup that grows on its own when more people use it and shrinks when they don't.
- A setup that keeps working if one server fails or is being updated.
- A database that is private, encrypted, and backed up every day.

### How long and how much

| Item | Answer |
| --- | --- |
| Time | About 2 hours the first time. Much of it is waiting for DigitalOcean to create things. |
| Cost while running | About $4.16 a day, roughly $125 a month. DigitalOcean bills by the hour, so if you delete everything (Part 8), billing stops. |
| Skills needed | Comfortable copying and pasting into a terminal. That's it. |

## Before you start: checklist

| You need | Why |
| --- | --- |
| A DigitalOcean account with a payment method or credit | Everything runs there. |
| A computer running Ubuntu 22.04 or newer, or Pop!\_OS | The commands in this guide are written for it. It must be a normal Intel/AMD computer (not ARM). |
| Permission to use `sudo` on that computer | Installing software needs administrator rights. |
| A login to Cloudflare for **nordheim.online** | To point the web address at the app (Part 4). |
| A password manager or a private notes file | You'll create several passwords. Keep them safe and never email them. Bitwarden is an open source and secure choice. |
| About 2 uninterrupted hours | Some steps depend on the one before. |

## The big picture (read this once)

Think of Drakkar Lite like a small restaurant:

- The **load balancer** is the host at the front door. Every visitor arrives there and is shown to a free table.
- The **Kubernetes cluster** is the kitchen. It's a group of servers (called **nodes**) where the app actually runs.
- The app runs as small copies called **pods**. There are two kinds: **web pods** serve the web pages, and **API pods** do the work behind them. When it gets busy, Kubernetes adds more API pods, like calling in extra cooks.
- The **database** is the locked pantry where all the data is kept. Only the kitchen has the key.
- The **container registry** is the recipe book: it stores the packaged app that the kitchen cooks from.

| Part | DigitalOcean product | What it does for you |
| --- | --- | --- |
| Front door | Load Balancer | One public address. Spreads visitors across servers. Created for you automatically in Step 17. |
| Kitchen | Kubernetes (DOKS) | Runs 2 servers normally and adds a 3rd when busy. Replaces anything that crashes. |
| Pantry | Managed PostgreSQL | Stores the data. Private, encrypted, backed up daily by DigitalOcean. |
| Recipe book | Container Registry | Holds the app packages (called **images**). |
| Padlock | Let's Encrypt, free | A free security certificate so the site works over https. |

## Part 1: Get your computer ready

### Step 1: Open a terminal

**What you're doing:** Opening the window where you type commands.

**Why:** Every step after this happens in the terminal. It's faster and less error-prone than clicking through web pages, and you can copy exactly what's written here.

**Do this:** Press **Ctrl + Alt + T**, or open the **Terminal** app from your applications menu. Keep it open for the whole guide.

Tip: to paste into the terminal, use **Ctrl + Shift + V** (not Ctrl + V).

### Step 2: Install the basic tools and Docker

**What you're doing:** Installing git (to download the code), Docker (to package the app) and a few helpers.

**Why:** DigitalOcean runs apps as **containers**, which are sealed packages that include everything the app needs. Docker is the tool that builds those packages.

```bash
sudo apt update
sudo apt install -y git curl python3 docker.io docker-buildx
sudo usermod -aG docker $USER
```

The last line lets you use Docker without typing `sudo` every time. **Log out of your computer and log back in** for it to take effect, then open the terminal again.

**Check it worked:**

```bash
git --version
docker version
docker buildx version
```

Each command prints a version number. If `docker version` says "permission denied", you haven't logged out and back in yet.

### Step 3: Install Flutter

**What you're doing:** Installing Flutter, the toolkit for building the Drakkar Lite web pages.

**Why:** Before the web pages can be packaged, Flutter must convert the source code into standard web files. It also includes Dart, in which the API is written.

**Do this:** Follow the official Linux instructions at **https://docs.flutter.dev/get-started/install/linux/web**. Choose the "Web" option, since you won't be building any Android apps for Drakkar.

**Check it worked:**

```bash
flutter --version
dart --version
```

Flutter should be 3.24 or newer, and Dart 3.5 or newer.

### Step 4: Download the Drakkar Lite code

**What you're doing:** Copying the app's code and setup files to your computer.

**Why:** Everything this guide deploys comes from these files: the app itself, the instructions Kubernetes follows (the `k8s` folders), and helper scripts that do the deep technical parts for you.

```bash
cd ~
git clone https://github.com/TaliskerMan/drakkar-lite-doks.git
cd ~/drakkar-lite-doks
chmod +x scripts/*.sh
```

**Check it worked:** Type `ls` and press ENTER. You should see folders including `k8s`, `k8s-tls`, `scripts`, `server`, and `web`.

### Step 5: Make sure the app builds on your computer

**What you're doing:** Running a single script to test and build the code.

**Why:** It's far easier to catch a problem here, on your own computer, than after it's been sent to DigitalOcean. If this passes, you know the tools from Steps 2–3 are set up correctly.

```bash
scripts/verify_build.sh
```

This takes several minutes the first time.

**Check it worked:** The last lines say **All checks passed**. If a step fails, the script names it. The most common cause is Flutter or Docker not being installed correctly, so go back to Step 2 or 3.

### Step 6: Create a DigitalOcean access token

**What you're doing:** Creating a key that lets your terminal act on your DigitalOcean account.

**Why:** The `doctl` tool (installed next) needs permission to create servers and databases for you. A token is like a password just for tools. You can revoke it at any time without changing your real password.

**Do this:**

1. Sign in at **https://cloud.digitalocean.com**.
2. Go to **API** in the left menu, then **Tokens**, then **Generate New Token**.
3. Name it `drakkar-setup`, pick an expiry (90 days is sensible), and choose **Full Access** (read and write).
4. Copy the token straight into your password manager. DigitalOcean shows it only once.

> **Keep this token secret.** Anyone who has it can create and delete things on your account and run up your bill. Never paste it into email, chat, or a document. If it ever leaks, delete it on the same Tokens page and make a new one.

### Step 7: Install the DigitalOcean and Kubernetes tools

**What you're doing:** Installing `doctl` (DigitalOcean's command-line tool), `kubectl` (the Kubernetes command-line tool), `helm` (used for HTTPS later) and two network helpers.

**Why:** `doctl` creates things on DigitalOcean. `kubectl` tells the cluster what to run. The included script installs them all from their official sources and verifies each download.

**Do this:** Run the script once. It installs `doctl`, then stops and asks you to sign in:

```bash
scripts/install_tools.sh
```

Sign in with the token from Step 6. When asked, paste the token and press Enter:

```bash
doctl auth init
```

Then run the script again to finish. The `K8S_MINOR` part tells it which Kubernetes version to match, because your cluster doesn't exist yet:

```bash
K8S_MINOR=1.36 scripts/install_tools.sh
```

**Check it worked:**

```bash
doctl account get
kubectl version --client
helm version
```

`doctl account get` shows your email address and status as **active**. The other two print version numbers.

### Step 8: Save your settings in one file

**What you're doing:** Writing down the names you'll use, once, so every later command can reuse them.

**Why:** Typing names by hand is the most common source of mistakes. With a settings file, a command like `$CLUSTER` always means the same thing. The file holds no passwords, so it's safe to keep.

**Do this:** Pick a **registry name**. It must be unique across all of DigitalOcean, lowercase, and use only letters, numbers, and dashes. For example, `nordheim-drakkar`. Then run the block below, replacing `nordheim-drakkar` if you chose something else:

```bash
cat > ~/drakkar-env.sh <<'EOF'
export REGION=nyc3
export REG=nordheim-drakkar
export CLUSTER=drakkar-demo
export DB=drakkar-demo-pg
export NS=drakkar
export TAG=v0.1.0
export REPO=~/drakkar-lite-doks
EOF
source ~/drakkar-env.sh
```

| Setting | Meaning |
| --- | --- |
| REGION | Which DigitalOcean data center to use. `nyc3` is New York. Everything must be in the same region so it can talk privately. |
| REG | Your registry (recipe book) name. |
| CLUSTER, DB | Names for the cluster and the database. |
| NS | The "namespace", a labeled area inside the cluster where Drakkar Lite lives. |
| TAG | The version label for this app release. |

> **Every time you open a new terminal**, run `source ~/drakkar-env.sh && cd $REPO` first. If a command complains about something being empty or missing, this is almost always why.

## Part 2: Create the DigitalOcean pieces

### Step 9: Set a spending alert and a project

**What you're doing:** Setting up email warnings about spending, and a folder in DigitalOcean that groups everything for Drakkar Lite.

**Why:** DigitalOcean has no hard spending limit. An alert warns you before a mistake, like a forgotten server, becomes an expensive one. The project provides a single screen showing every piece and its cost.

**Do this:**

1. On the DigitalOcean website, go to **Billing**, then **Spend alerts**. Create an alert for your monthly budget (for example, $150). Add warnings at 50%, 75%, 90%, and 100% to alert you as you near your budget constraints.
2. Create the project in the terminal:

   ```bash
   doctl projects create --name "Drakkar Lite" --purpose "Web Application" --environment Production
   ```

3. On the website, open **Projects**, click the three dots next to **Drakkar Lite**, and choose **Make default**. From now on, everything you create lands in this project.

**Check it worked:** The Drakkar Lite project appears in the left menu marked as default, and the spend alert is listed under Billing.

### Step 10: Create the container registry

**What you're doing:** Creating the private storage where the packaged app will live.

**Why:** Your servers need somewhere to download the app from. A private registry at DigitalOcean is close to the servers (so downloads are fast) and only your account can use it. The Basic plan costs $5 a month.

```bash
doctl registry create $REG --subscription-tier basic --region $REGION
doctl registry login
```

**Check it worked:** `doctl registry get` shows your registry name. If you get "name already taken", choose a different name, update `REG` in `~/drakkar-env.sh`, run `source ~/drakkar-env.sh`, and try again.

### Step 11: Create the Kubernetes cluster

**What you're doing:** Creating the group of servers that runs the app.

**Why each setting matters:**

- **2 servers, growing to 3 when busy** (`min-nodes=2;max-nodes=3`). Two servers means one can fail and the app keeps running. The 3-server limit also caps your bill.
- **Server size `s-2vcpu-4gb`** (2 CPUs, 4 GB memory, $24/month each). Big enough for the app with room to spare. Measurements show each server using about a third of its memory.
- **High-availability control plane** (`--ha`). The control plane is the "brain" that manages the cluster. The HA version keeps it running during DigitalOcean's own maintenance and comes with a 99.95% uptime promise. It costs $40 a month. **Once turned on, it can't be turned off.** DigitalOcean turns it on by default for new clusters.
- **metrics-server**. Measures how busy each pod is. Without it, the app can't grow automatically.

```bash
doctl kubernetes cluster create $CLUSTER \
  --region $REGION --version latest --ha \
  --node-pool "name=default;size=s-2vcpu-4gb;count=2;auto-scale=true;min-nodes=2;max-nodes=3" \
  --1-clicks metrics-server
doctl kubernetes cluster registry add $CLUSTER
```

The first command takes 5–10 minutes. When it finishes, it sets up `kubectl` to talk to the new cluster. The second command gives the cluster permission to download from your registry.

**Check it worked:**

```bash
kubectl get nodes
kubectl get gatewayclass cilium
kubectl top nodes
```

You should see **2 nodes** with status **Ready**. The `cilium` line shows **ACCEPTED True**. `kubectl top nodes` shows CPU and memory numbers. If it says "metrics not available", wait 3 minutes and try again.

### Step 12: Create the database

**What you're doing:** Creating the managed PostgreSQL database, a database inside it called `drakkar`, and a login the app will use.

**Why:** "Managed" means DigitalOcean handles backups, security updates and repairs, so you don't have to. The app has its **own login** (`drakkar_app`) with limited rights, rather than the all-powerful admin login. That means even a bug in the app can't let one customer see another customer's contacts. The database enforces that separation itself.

```bash
doctl databases create $DB --engine pg --region $REGION \
  --size db-s-1vcpu-1gb --num-nodes 1 --wait
```

This takes 5–10 minutes. Then, when it has finished:

```bash
DB_ID=$(doctl databases list --format ID,Name --no-header | awk -v n=$DB '$2==n{print $1}')
echo "export DB_ID=$DB_ID" >> ~/drakkar-env.sh
doctl databases db create $DB_ID drakkar
doctl databases user create $DB_ID drakkar_app
```

**Check it worked:** `doctl databases list` shows your database with status **online**.

### Step 13: Lock the database down and collect its details

**What you're doing:** Allowing only your cluster to connect to the database, then noting the private address and passwords.

**Why:** By default, the database can be reached from the internet if someone has the password. The firewall rule means only your cluster can even knock on the door. You'll use the **private** address, so data between the app and the database never leaves DigitalOcean's internal network.

```bash
CLUSTER_ID=$(doctl kubernetes cluster get $CLUSTER --format ID --no-header)
doctl databases firewalls append $DB_ID --rule k8s:$CLUSTER_ID
doctl databases connection $DB_ID --private --format Host,Port,User,Password
doctl databases user get $DB_ID drakkar_app --format Name,Password
```

**Copy these three values into your password manager:**

| Label | Where it comes from |
| --- | --- |
| PRIVATE\_HOST | The **Host** from the `connection` command. It starts with `private-`. |
| ADMIN\_PW | The **Password** from the `connection` command (the `doadmin` user). |
| APP\_PW | The **Password** from the `user get` command (the `drakkar_app` user). |

If your version of doctl doesn't recognize `--private`, get the same details on the website: **Databases**, then **drakkar-demo-pg**, then **Connection details**, then choose **VPC network**.

**Check it worked:** `doctl databases firewalls list $DB_ID` shows one rule of type **k8s**. You have all three values saved.

## Part 3: Put the app on the cluster

### Step 14: Package the app and upload it

**What you're doing:** Building the two app packages (web and API) and uploading them to your registry.

**Why:** The cluster can only run what's in the registry. The `--platform linux/amd64` option ensures the package is compatible with DigitalOcean's servers. If you ever build on an Apple Silicon Mac, leaving it out produces a package the servers can't run. The first command points the setup files at **your** registry name.

```bash
source ~/drakkar-env.sh && cd $REPO
scripts/set_registry.sh $REG $TAG
(cd web && flutter build web --release --no-web-resources-cdn)

docker buildx build --platform linux/amd64 -f server/Dockerfile \
  -t registry.digitalocean.com/$REG/drakkar-api:$TAG --push .
docker buildx build --platform linux/amd64 \
  -t registry.digitalocean.com/$REG/drakkar-web:$TAG --push web
```

**Check it worked:**

```bash
doctl registry repository list-v2
```

It lists **drakkar-api** and **drakkar-web**. If `docker push` says "unauthorized", run `doctl registry login` again and repeat the build commands.

### Step 15: Give the cluster the database passwords

**What you're doing:** Storing the two database connection details inside the cluster as a **Secret**.

**Why:** The app needs the password to access the database, but passwords must never be written into code or configuration files, where they could be copied or published by accident. A Kubernetes Secret keeps them inside the cluster only. There are two logins: the everyday one for the app (`drakkar_app`), and the admin one (`doadmin`), used only to set up the database tables.

**Do this:** Replace `<APP_PW>`, `<ADMIN_PW>` and both `<PRIVATE_HOST>` with your saved values. Remove the `< >` brackets too.

```bash
kubectl apply -f k8s/namespace.yaml
kubectl -n $NS create secret generic drakkar-db \
  --from-literal=DATABASE_URL="postgresql://drakkar_app:<APP_PW>@<PRIVATE_HOST>:25060/drakkar?sslmode=require" \
  --from-literal=MIGRATOR_DATABASE_URL="postgresql://doadmin:<ADMIN_PW>@<PRIVATE_HOST>:25060/drakkar?sslmode=require"
```

Tip: if you start the command with a space, most terminals won't save it in your command history.

**Check it worked:** `kubectl -n $NS get secret drakkar-db` shows the secret with **2** in the DATA column.

### Step 16: Set up the database tables

**What you're doing:** Running a one-time job that creates the tables the app uses to store data.

**Why:** The database starts empty. This job (called a **migration**) creates the tables and security rules **before** the app starts, so the app never finds a database it doesn't understand. You'll re-run it with every new version of the app.

```bash
kubectl -n $NS delete job drakkar-migrate --ignore-not-found
kubectl apply -k k8s/migrate
kubectl -n $NS wait --for=condition=complete job/drakkar-migrate --timeout=180s
kubectl -n $NS logs job/drakkar-migrate
```

**Check it worked:** The log ends with **migrations complete**. If it says "timed out" or shows a connection error, check the Secret values from Step 15 (see Part 7).

### Step 17: Start the app

**What you're doing:** Telling the cluster to run the app, route visitors to it, and automatically scale it.

**Why:** This single command applies every setup file in the `k8s` folder. It starts 2 web pods and 2 API pods on different servers, so losing a server doesn't take the app down. It sets up automatic scaling to 5 API pods when CPU usage exceeds 70%. And it creates the **Gateway**, which requests a load balancer from DigitalOcean (the front door).

```bash
kubectl apply -k k8s
kubectl -n $NS rollout status deploy/drakkar-api
kubectl -n $NS rollout status deploy/drakkar-web
kubectl -n $NS get pods -o wide
```

**Check it worked:** Both rollout commands say **successfully rolled out**. The pod list shows 4 pods, all **Running** and **1/1** ready, with the two API pods on different nodes.

### Step 18: Get the app's public address and test it

**What you're doing:** Waiting for the load balancer, then testing the app through it.

**Why:** The load balancer is how the public reaches the app. It takes a few minutes for DigitalOcean to create it and give it an IP address. The tests prove that the web pages load, that the API responds, and that one organization can't see another's data.

```bash
kubectl -n $NS get gateway drakkar -w
```

Wait until an IP address appears in the **ADDRESS** column (usually 2–5 minutes), then press **Ctrl + C** to stop watching.

```bash
export LB_IP=$(kubectl -n $NS get gateway drakkar -o jsonpath='{.status.addresses[0].value}')
echo $LB_IP
curl -s -o /dev/null -w '%{http_code}\n' http://$LB_IP/
curl -s -o /dev/null -w '%{http_code}\n' http://$LB_IP/v1/auth/me
scripts/isolation_demo.sh http://$LB_IP
```

**Check it worked:**

- The first curl prints **200**, which means the web pages load.
- The second prints **401**. That is correct: it means the API answered and refused a visitor who isn't signed in.
- The isolation test ends with **Tenant isolation holds.**
- Opening `http://` followed by your IP in a browser shows the Drakkar Lite sign-up page.

**Write down the IP address.** You need it in Part 4.

## Part 4: Turn on HTTPS (the padlock)

Right now the app only works over plain `http://`, which isn't encrypted. Browsers mark it "Not secure". Security certificates can only be issued for web addresses, not bare IP addresses, so first you point a name at the app.

### Step 19: Point drakkar.nordheim.online at the load balancer

**What you're doing:** Adding one DNS record at Cloudflare so the name **drakkar.nordheim.online** leads to your load balancer.

**Why:** DNS is the internet's phone book: it turns names into IP addresses. The nordheim.online phone book is hosted on Cloudflare, so the record is stored there. Nothing else in Cloudflare changes, and email is not affected.

**Do this:** In the Cloudflare dashboard, open **nordheim.online**, then **DNS**, then **Records**. Add a record, or edit the existing `drakkar` record:

| Field | Value |
| --- | --- |
| Type | A |
| Name | `drakkar` (just this word; Cloudflare adds the rest) |
| IPv4 address | Your load balancer IP from Step 18 |
| Proxy status | **DNS only (grey cloud)**. This is important; see below. |
| TTL | Auto |

> **The cloud must be grey, not orange.** An orange cloud makes Cloudflare stand in the middle of the connection. The certificate check in the next step then fails, and visitors see Cloudflare's certificate instead of yours.

**Check it worked:** Wait 1–5 minutes, then:

```bash
dig +short A drakkar.nordheim.online @1.1.1.1
```

It must print **exactly** your load balancer IP. Don't continue until it does. Each failed certificate attempt uses up one of a small weekly allowance.

### Step 20: Get the certificate and switch on HTTPS

**What you're doing:** Running a single script to install a certificate manager in the cluster, obtain a free certificate from Let's Encrypt, and enable HTTPS.

**Why:** **cert-manager** is a small helper that fetches and renews the certificate automatically about every 60 days, so it never expires unexpectedly. The script checks everything first (DNS, the load balancer, port 80) and stops with a clear message if something isn't ready. After this, anyone visiting `http://drakkar.nordheim.online` is automatically redirected to the secure `https://` version. This costs nothing extra.

```bash
source ~/drakkar-env.sh && cd $REPO
scripts/enable_tls.sh
```

This takes 3–5 minutes. Want a practice run first? `STAGING=1 scripts/enable_tls.sh` uses Let's Encrypt's test service, which has no limits. The browser won't trust that practice certificate, so run the normal command afterward.

**Check it worked:**

```bash
scripts/tls_check.sh drakkar.nordheim.online
```

Every line should pass. Then open **https://drakkar.nordheim.online** in a browser and confirm the padlock appears.

### Step 21: Back up the certificate

**What you're doing:** Saving a private copy of the certificate.

**Why:** The certificate lives inside the cluster. If the cluster is ever deleted and rebuilt, restoring this copy avoids using up the weekly certificate allowance.

```bash
mkdir -p ~/drakkar-private
kubectl -n $NS get secret drakkar-tls -o yaml \
  | sed '/resourceVersion:/d;/uid:/d;/creationTimestamp:/d;/^\s*selfLink:/d' \
  > ~/drakkar-private/drakkar-tls.yaml
grep -c 'tls.crt\|tls.key' ~/drakkar-private/drakkar-tls.yaml
```

**Check it worked:** The last command prints **2**.

> **This file contains the certificate's private key. Treat it like a password.** Keep it outside the code folder, never email it, and delete it when the app is retired.

## Part 5: Final checks

**What you're doing:** Confirming everything works end-to-end, like a real user would.

**Why:** The earlier checks tested each piece individually. This tests the whole thing together.

1. Open **https://drakkar.nordheim.online**. Create an organization and add a few contacts.
2. Refresh the page a few times. The **"served by"** text at the bottom changes, which shows visitors are being shared across pods.
3. In the terminal:

   ```bash
   scripts/isolation_demo.sh https://drakkar.nordheim.online
   kubectl -n $NS get hpa
   ```

   The isolation test passes. The `hpa` line shows a percentage under TARGETS (not `<unknown>`), which means automatic growth is working.
4. On the DigitalOcean website, open the **Drakkar Lite** project. You should see one cluster, one load balancer (`drakkar-lite-lb`) showing healthy nodes, one database, and one registry.

**Setup is done.**

## Part 6: Everyday care

> **Important:** now that HTTPS is on, always use `kubectl apply -k k8s-tls`, not `kubectl apply -k k8s`. The `k8s-tls` folder includes everything in `k8s` **plus** the HTTPS settings. Using plain `k8s` would quietly switch HTTPS off.

### Check the cost (once a week)

```bash
BUDGET=150 scripts/cost_check.sh
```

This lists everything you're paying for and the current hourly cost. It catches forgotten extras, like a second load balancer, before they add up.

### Release a new version of the app

**Why this order:** the database is updated first, so the new app never starts against old tables. Pods are then replaced one at a time, so visitors see no downtime.

```bash
source ~/drakkar-env.sh && cd $REPO && git pull
export TAG=v0.1.1          # use the new version number
scripts/set_registry.sh $REG $TAG
# Repeat the build-and-upload commands from Step 14, then:
kubectl -n $NS delete job drakkar-migrate --ignore-not-found
kubectl apply -k k8s/migrate
kubectl -n $NS wait --for=condition=complete job/drakkar-migrate --timeout=180s
kubectl apply -k k8s-tls
kubectl -n $NS rollout status deploy/drakkar-api
```

Also update `TAG` in `~/drakkar-env.sh` so it matches.

### Undo a bad release

```bash
kubectl -n $NS rollout undo deploy/drakkar-api
kubectl -n $NS rollout undo deploy/drakkar-web
```

This switches back to the previous version within a minute or two.

### Change the app's database password

Do this if you think a password has leaked, or on a regular schedule.

```bash
doctl databases user reset $DB_ID drakkar_app
doctl databases user get $DB_ID drakkar_app --format Name,Password
```

Then delete the Secret with `kubectl -n $NS delete secret drakkar-db`, create it again as in Step 15 with the new password, and restart the API: `kubectl -n $NS rollout restart deploy/drakkar-api`.

### Kubernetes updates

DigitalOcean releases new Kubernetes versions regularly. To see whether one is available:

```bash
doctl kubernetes cluster get-upgrades $CLUSTER
```

To upgrade, run `doctl kubernetes cluster upgrade $CLUSTER --version <version>`. Servers are replaced one at a time, and the app's safety rules (called **PodDisruptionBudgets**) ensure at least one copy of each part is running at all times.

### Database backups

DigitalOcean backs up the database every day automatically, at no extra cost. To see them: `doctl databases backups $DB_ID`. To restore, create a copy of the database from a backup in the website (**Databases**, then **drakkar-demo-pg**, then **Backups**).

## Part 7: When something goes wrong

Start with these two commands. They answer most questions:

```bash
kubectl -n $NS get pods
kubectl -n $NS get events --sort-by=.lastTimestamp | tail -20
```

| What you see | What it usually means | What to do |
| --- | --- | --- |
| A command says a name is empty or "required" | The settings file isn't loaded in this terminal | `source ~/drakkar-env.sh && cd $REPO` |
| Pods show **ImagePullBackOff** | The cluster can't download the app from the registry | Run `doctl kubernetes cluster registry add $CLUSTER`. Check that Step 14 finished and that `scripts/set_registry.sh` used your registry name. |
| Pods show **exec format error** | The package was built for the wrong kind of computer | Rebuild with `--platform linux/amd64` exactly as in Step 14. |
| API pods never become ready | Wrong database address or password in the Secret | Run `kubectl -n $NS logs deploy/drakkar-api`. Make sure the Secret uses the **private-** host and the right passwords. Recreate the Secret (Step 15), then run `kubectl -n $NS rollout restart deploy/drakkar-api`. |
| Migration says **permission denied** | The admin address in the Secret uses the wrong login | `MIGRATOR_DATABASE_URL` must use `doadmin`. Fix the Secret and repeat Step 16. |
| HPA shows `<unknown>` or `kubectl top` fails | metrics-server is missing or still starting | Wait 3 minutes. If it's still failing: `doctl kubernetes 1-click install $CLUSTER --1-clicks metrics-server` |
| Gateway has no ADDRESS after 10 minutes | The load balancer is stuck | Run `kubectl -n $NS describe gateway drakkar` and read the messages. As a backup: `kubectl -n $NS apply -f k8s/extras/web-loadbalancer.yaml`, then use the EXTERNAL-IP from `kubectl -n $NS get svc`. |
| HTTPS script says the name **resolves to** a different address | The Cloudflare record is wrong, or the cloud is orange | Fix the record (Step 19), make sure the cloud is grey, wait 5 minutes, try again. |
| Browser says the certificate is "not trusted" | The practice (STAGING) certificate is still in use | Run `kubectl -n $NS delete secret drakkar-tls`, then `scripts/enable_tls.sh` without STAGING. |
| Database says **too many connections** | Too many API pods for the small database plan | Don't raise the 5-pod limit without moving to a bigger database plan first. |
| HTTPS stopped working after an update | `kubectl apply -k k8s` was used instead of `k8s-tls` | Run `kubectl apply -k k8s-tls`. |

## Part 8: Shutting it all down

**What you're doing:** Deleting everything so billing stops.

**Why:** DigitalOcean charges by the hour for as long as things exist, even if nobody is using them. Deleting in this order makes sure nothing is left behind.

> **This can't be undone.** All data in the database is deleted. Export anything you need first.

```bash
source ~/drakkar-env.sh
doctl kubernetes cluster delete $CLUSTER --dangerous
doctl databases delete $DB_ID
doctl registry delete
doctl compute load-balancer list
doctl compute volume list
```

The `--dangerous` flag also deletes the load balancer and storage the cluster created. The last two commands should print empty lists.

Then finish up:

1. **Delete the Cloudflare record** for `drakkar`. Otherwise the name keeps pointing at an IP address DigitalOcean may later give to someone else.
2. Delete the certificate backup: `rm -rf ~/drakkar-private`
3. Delete the API token (DigitalOcean website, **API**, then **Tokens**).

### Rebuilding later

Follow Parts 2–4 again, from Step 10. The load balancer gets a **new IP address**, so update the Cloudflare record in Step 19. Before running Step 20, restore the certificate backup with `kubectl -n $NS apply -f ~/drakkar-private/drakkar-tls.yaml`, if you kept it.

## Glossary

| Term | Plain meaning |
| --- | --- |
| Cluster | A group of servers managed together as one. |
| Node | One server in the cluster. |
| Container / image | A sealed package holding the app and everything it needs. The image is the package; a container is a running copy of it. |
| Pod | One running copy of part of the app, inside the cluster. |
| Deployment | The rule that says "keep this many pods of this image running". |
| Namespace | A labeled area inside the cluster that keeps Drakkar Lite's pieces together. |
| Service | A stable internal address for a group of pods. |
| Gateway | The entrance that sends `/v1/...` requests to the API and everything else to the web pages. It also creates the load balancer. |
| Load balancer | The public front door that shares visitors across the servers. |
| HPA (Horizontal Pod Autoscaler) | Adds API pods when they're busy (above 70% CPU) and removes them when it's quiet. 2 to 5 pods. |
| Cluster Autoscaler | Adds a server when the existing ones are full, and removes it later. 2 to 3 servers. |
| PodDisruptionBudget (PDB) | A safety rule that stops maintenance from taking every copy of the app down at once. |
| Secret | A protected place in the cluster for passwords. |
| Job / migration | A task that runs once and finishes; here, setting up the database tables. |
| Control plane | The cluster's "brain" that decides what runs where. DigitalOcean runs it for you. |
| TLS / HTTPS / certificate | Encryption between the visitor's browser and the app, shown by the padlock. The certificate proves the site is really drakkar.nordheim.online. |
| DNS / A record | The internet's phone book entry that turns a name into an IP address. |
| doctl / kubectl | Command-line tools for DigitalOcean and for Kubernetes. |
