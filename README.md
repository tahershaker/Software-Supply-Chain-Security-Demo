# Software Supply Chain Security Demo

> See software supply chain security in action. We follow one small web application from its source code to a running service. We check the code, package it, find and fix its vulnerabilities, move to secure images to shrink the attack surface, then sign it, store it in a private registry and run it on Kubernetes. Everything runs on an environment that we build on AWS.


---

## Contents

* [Description](#description) - what this demo is, and why software supply chain security matters.
* [Strategy](#strategy) - the plan, the order of work, and the tools we use and why.
* [High-Level Steps and Actions](#high-level-steps-and-actions) - what we do, why we do it, and the business value of each action.
* [Infrastructure](#infrastructure) - what we build on AWS, and what each part is used for.
* [Deploying the Environment](#deploying-the-environment) - build the AWS environment, check it, and install Harbor.
* [Step-By-Step](#step-by-step) - the full guide, section by section.
* [References](#references) - links for further reading.

---

## Description

When you build an application, you do not write every line yourself. You use libraries that other people wrote. You start from a base image that other people made. You use tools to build, test and ship it. So your application is made of many parts, and they come from many places. Each part is a link in a chain.

Now ask a few questions. What if one link has a known security bug? Then your application has the same bug, and you may not know it. A known security bug is called a **vulnerability**, and it gets a public ID called a **CVE**. So how do you know if a CVE is in your own code, in your libraries, or in your base image? How serious is it? Should you put an image that has a known CVE into production? If not, how do you fix it? And how do you make sure you have fewer of them next time? A vulnerability does not go away by itself. Someone must find it and fix it, or attackers will use it.

Here is a simple way to see it. Every part you add to your application is a possible door for an attacker. More parts mean more doors. This is called the **attack surface**. Open-source software is a great thing, but it is not free of risk. So the best fix is not only to patch what you find. It is also to let in only what you really need, and to keep that small set up to date. Reducing the attack surface of the open-source software you use is the core of **secure open source**.

There are questions about trust as well. How fast can you find every application that uses a vulnerable link? How can you prove that the image running in production is the one you built, and that nobody changed it on the way? Together, all these questions are the topic of **software supply chain security**.

Here is a real example. In December 2021, a serious bug was found in Log4j, a very popular Java library. Companies all over the world had to ask: "Do we use it? Where?" Many needed days or weeks to answer. Teams that knew exactly what was inside their software could answer in hours.

**This repository is a hands-on demo of these ideas.** We take one small web application and follow it from source code to a running service on Kubernetes. On the way, we look at the security of every step.

In simple words, this is what we do:

1. We **check the code first**, before we build anything. We scan our own code and the libraries it uses. This is the "shift left" idea of DevSecOps.
2. We build the application as it is, with an old open-source image, and we scan it. In production, this work is normally done by a CI/CD pipeline, and this build would never happen. The pipeline would stop at the code check in step 1, because it finds critical issues and vulnerabilities. In this demo, we build anyway, on purpose and without a pipeline, to learn what the scanners find in an image.
3. We **fix** the code and the libraries, move to a newer open-source image, rebuild, and scan again. Some vulnerabilities will remain.
4. We switch to a **secure image** from `Chainguard`. Before we use it, we check who built it: we verify its signature and read its SBOM (a list of everything inside the image). Then we build and scan again.
5. We reduce the attack surface further with a **multi-stage build**. We build the application in the `Chainguard` development image (the `-dev` variant), and we run it in a minimal, distroless `Chainguard` image. We scan and compare all the results.
6. We run the final image as a standalone container.
7. We create SBOMs, store all the images in a private registry that scans images, sign the final image, and set rules that block images that are not safe.
8. We deploy the final image to a Kubernetes cluster and expose it to the public.

The application and the exercise come from a `chainguard` repository. It contains a small web application written in Go, and its libraries have known vulnerabilities. To understand the exercise in more detail, please check this repository: [chainguard-technical-challenge](https://github.com/maligin/chainguard-technical-challenge).

For the secure images, we use the container images from `Chainguard`. We compare them with the open-source images, to see what a secure base changes.

To do all this in a realistic setting, we also build an environment on AWS using a Terraform script. The Terraform script creates a private and a public network, one work machine (the `bastion`), and a small Kubernetes cluster with three nodes (one `master` node and two `worker` nodes) running `RKE2`. A load balancer is the public entry point. On the cluster, we install Harbor, an open-source private registry, and later we deploy the application. You can find more details in the [Infrastructure](#infrastructure) section.

> **Do not use in production.** This is a demo for learning. The environment is simple on purpose, and some settings (for example, skipping certificate checks for a private registry) are not safe for a real production system.

---

## Strategy

> **The idea in one paragraph**

In this demo, we want to understand and show the value of **secure images**, **multi-stage builds** and **distroless images**. We also want to understand the full idea of **software supply chain security**: where vulnerabilities can come from, how to find them, and how to reduce them. What we do is simple. We take a small Go application from the [Chainguard Technical Challenge repository](https://github.com/maligin/chainguard-technical-challenge). It is a web application, built with the Gin framework, and it only answers "Hello World!". We follow it from source code to a running service. We check the code first. Then we find out where the vulnerabilities come from, and we remove them in steps. We scan after every step. At the end, we prove that the final image can be trusted, and we run it on Kubernetes.

> **Why we start with the code: shift left**

Think of the path of an application as a line from left to right. We write the code, we build it, we package it into an image, we store the image, and we run it. The "left" is the start of this line.

If you find a security problem at the left, it is cheap to fix. You change a line of code or update a library, and you move on. If you find the same problem at the right, in production, it is expensive. The image is built, stored and running, and you must stop, fix, build, test and deploy again. So modern teams **shift left**. This means they check security as early as possible. This idea is part of **DevSecOps**.

This is why we start with the code, and not with an image.

> **What do we check in the code?**

We check two things.

1. **SAST** (Static Application Security Testing). A SAST tool reads our own source code and looks for risky patterns, such as weak settings or unsafe functions.
2. **SCA** (Software Composition Analysis). An SCA tool looks at the libraries we use and compares them with a database of known vulnerabilities.

Our application is very small, so there is almost no code of our own to check. Most of the risk is in the libraries. A SAST tool alone would miss this. This is why we use both kinds of check.

> **What happens in a real environment, and what we do here**

In the real world, nobody builds and checks images by hand. The team uses a CI/CD pipeline, built with tools such as Jenkins, GitLab CI or GitHub Actions.

It works like this. A developer writes code and pushes it to a Git repository, for example GitHub. The developer then makes a commit or opens a merge request. This starts the pipeline automatically (in most cases). The pipeline scans the code, checks it and tests it. If all the checks pass, it builds the container image from the source code. If a check fails, the pipeline stops.

In this demo, we do not use a pipeline. We do every step by hand. The reason is simple. This is a demo to show value and to learn, and we want to see every step and every result.

> **Where do vulnerabilities come from?**

A container image is made of layers, and each layer comes from a different place. For our Go application, a vulnerability can come from four places:

1. **Our own code.** The few lines we wrote. SAST checks this part.
2. **The libraries.** These are the libraries listed in the `go.mod` file, such as the Gin web framework. SCA checks this part.
3. **Go itself.** A Go program carries a part of the Go standard library inside its binary. If we build with an old Go version, we also carry the old bugs.
4. **The base image.** This is the Linux system inside the image, for example Debian. It has many packages, and each package can have bugs.

When we scan an image, the scanner tells us the type of each finding (operating system package, Go library, Go standard library). So even when we change several things at once, we can still see which part each change helped.

> **The images we build**

We build four images. They tell the story in order, and we change one thing at a time where we can.

| Image | Code and libraries | Go | Base image | Build style | What it shows |
|:---|:---|:---|:---|:---|:---|
| `hello-oss-single-v1` | Original | 1.18 (old) | Old open-source Go image | Single-stage | The starting point: problems from the code, the libraries, Go and the base image. |
| `hello-oss-single-v2` | Fixed | Current | Current open-source Go image | Single-stage | What fixing the code, the libraries and the image gives us. |
| `hello-cg-single` | Fixed | Current | secure `Chainguard` Go development image | Single-stage | What changes when only the base image changes. |
| `hello-cg-multi` | Fixed | Current | secure `Chainguard` Go development image to build, secure `Chainguard` minimal image to run | Multi-stage | What changes when only the build style changes, and the attack surface becomes as small as possible. |

Look at the pairs. Between `v2` and `cg-single`, the only change is the base image. Between `cg-single` and `cg-multi`, the only change is the build style. This is why the comparisons are fair.

> **Why a secure image?**

After we fix our code and update everything, some findings remain in the open-source image. We cannot remove them by updating, for example because no fix exists yet. So what can we do? We have three options.

- **Option 1: fix it ourselves.** We find the issue, fix it, and patch the image. This takes time and skill for every finding. It also moves our image away from the open-source version. This is called drift. We now own the patch, and we must keep it working.
- **Option 2: wait for the open-source community.** We wait until the community releases a fix. We do not control when this happens. Until then, we run with the vulnerability.
- **Option 3: use a secure image.** A secure image provider takes the same open-source software and builds it from source. It keeps the image as small as it can, and it fixes vulnerabilities without waiting for the community. We get the same open source with as few CVEs as possible. We have no patches to maintain, and no drift.

In this demo, we use option 3, with the images from `Chainguard`. We compare them with the open-source images to see the difference.

A secure single-stage image improves the CVE count, but some CVEs can remain, because it still carries the build tools. The next step is to remove them.

> **Why a multi-stage build?**

A single-stage image builds and runs the application in the same image. So the compiler and the build tools travel to production, and the application does not need them to run.

A **multi-stage** build splits the work. The first stage is a development image. It has the compiler and the tools, and it builds the application. The last stage is a minimal, distroless image. It has almost nothing in it. We copy only the finished application into it, and we change nothing else. The final image has no compiler, no shell and no package manager, so the attack surface is much smaller.

> **Check before you use: who built this image?**

Before we use an image that someone else built, we should ask three questions. Who built it? Was it changed on the way? What is inside it? The secure images are signed, and they publish an SBOM. So before every secure build, we pull the image, check the signature with Cosign, and read its SBOM. Only then do we build. We also pin the image by its digest, which is a fingerprint, so we build on exactly the image that we checked.

> **How we read the results**

* **Two scanners, not one.** Scanners use different databases and different rules, so they can give different numbers. We use two and compare them.
* **Reachability.** A scanner lists everything that is installed. It does not say if the program really uses the vulnerable code. We use a Go tool to check this, so we can tell which findings matter most.
* **Fixable or not.** For every finding, we ask: is there a fixed version? If yes, we update. If no, we cannot fix it by updating, and we must think about using a secure image or a smaller image.
* **Evidence.** We save the raw scan files, the date of each scan, and the version of each tool. Vulnerability data changes every day, so numbers can differ from one day to the next. Saved evidence lets us explain our numbers later.

> **The tools and why we use them**

| Tool | What it does | Why we use it |
|:---|:---|:---|
| **Terraform** | Creates the AWS environment from code. | The environment is repeatable. Anyone can create it again with a few commands. |
| **AWS** (VPC, EC2, load balancer) | Network, servers and the public entry point. | A realistic cloud setting with a public and a private network. |
| **RKE2** | An open-source Kubernetes distribution. | Simple to install, secure by default, and a good fit for a small cluster. |
| **kubectl** and **Helm** | Talk to Kubernetes, and install packaged applications. | The standard way to manage a cluster and to install Harbor. |
| **local-path-provisioner** | Gives the cluster simple disk storage on the nodes. | Harbor needs disk space to store images. |
| **Ingress controller** | One entry door for web traffic into the cluster. | Harbor and our application can share one public entry point. |
| **Harbor** | Open-source private container registry. | It stores images, scans them, shows SBOMs and signatures, and can enforce rules. |
| **Chainguard images** | Secure open-source container images, rebuilt often and published with a signature and an SBOM. | The same open source with as few CVEs as possible, without waiting for the community to ship fixes. |
| **gosec** | SAST tool for Go. Reads our code and warns about risky patterns. | Checks our own code before we build. |
| **govulncheck** | Official Go tool. Checks if vulnerable code is really used. | It separates findings that matter from findings that are only listed. |
| **Trivy** | Open-source scanner for code, images and Kubernetes files. | Checks libraries in the code, scans images, and checks our Kubernetes files. Harbor uses Trivy too, so we can compare. |
| **Grype** | Open-source vulnerability scanner. | The second scanner for images. It can also scan an SBOM without the image. |
| **Docker** | Builds and runs container images. | The most common tool for this work, and it works the same everywhere. |
| **Hadolint** | Checks a Dockerfile for common mistakes. | Catches bad habits before we build. |
| **Syft** | Creates an SBOM from an image. | An SBOM tells us exactly what is inside an image. |
| **Cosign** | Signs and verifies images and SBOMs. | We use it to check the signature and the SBOM of the secure images before we use them, and to sign our own final image. |
| **jq** | Reads and filters JSON files. | Scan results are JSON, and jq helps us count and compare them. |

---

---

# High-Level Steps and Actions

This is a short overview of what we do and why we do it. The detailed commands are in the [Step-By-Step](#step-by-step) section.

**1. Build the environment:** We use Terraform to create a network, a work machine, a Kubernetes cluster and a registry. | *Why:* Code-based environments are repeatable, easy to review and quick to create again. In this demo, we need a realistic place to build, store and run the images, and we want anyone to be able to repeat it.

**2. Check our code and our libraries (shift left):** Before we build anything, we scan our own code (SAST) and the libraries it uses (SCA). | *Why:* The earlier you find a problem, the cheaper it is to fix. A fix in a source file takes minutes. The same fix in production takes days. In this demo, we need to know which vulnerabilities and flaws come from our own code and libraries, so we can follow them through the flow and see later which ones are still there.

**3. Build the image as it is, and scan it:** We build the unfixed application in a single-stage image with an old open-source base image, and we scan it with two scanners. | *Why:* Scanning an image shows you what is inside it and which known vulnerabilities it carries, including the ones that come from the base image and the libraries. The scan turns risk into numbers (CVEs by severity), and these numbers become the baseline that lets you prove later that things got better. In this demo, we use code that we already know has issues, to show the idea and to improve understanding.

**4. Understand which findings matter:** We group the findings by source, compare the two scanners, check which findings have a fix, and check which vulnerable code the program really uses. | *Why:* A long list of findings is not a plan. Teams need to know where to start, so they do not waste time on alerts that do not matter. In this demo, we want to show where vulnerabilities come from (code, libraries, Go, base image), so we can see later what each step helped.

**5. Fix the code, the libraries and the image, then scan again:** We update the libraries, fix a code warning, move to a current Go version and a current open-source image, and build again. | *Why:* Updating is usually the cheapest fix, and one update can remove many findings at once. In this demo, we want to see how far updating can go. Some findings will remain, because no fix exists for them yet, and this leads to the next step.

**6. Check the secure image, then use it (single-stage):** We pull the secure image, verify its signature, read its SBOM, and pin it by digest. Then we build, scan and compare. | *Why:* When a finding has no fix, you can fix it yourself, wait for the open-source community, or use a secure image that is built from the same open source with as few CVEs as possible. You should also never trust an image only because of its name. In this demo, we want to show the value of a secure image, and we check who built it and what is inside before we use it.

**7. Reduce the attack surface with a multi-stage build:** We build the application in a development image and run it in a minimal, distroless image. We check this image the same way, then scan and compare everything. | *Why:* The compiler and the build tools are not needed to run the application. Every extra tool is a possible vulnerability and a possible tool for an attacker. In this demo, we want to show how much smaller the attack surface becomes when only the finished application is left in the final image.

**8. Run the final image with safe settings:** We run it as a standalone container, with a non-root user, a read-only file system and no extra Linux powers. | *Why:* Even a good image can have a bug that nobody knows yet, so we limit what an attacker can do. This is the "least privilege" idea. In this demo, we want to prove that the final image runs correctly with these tight settings.

**9. Create SBOMs:** We create a Software Bill of Materials (SBOM) for each image. It is a list of every package, library and tool inside the image, with their versions. | *Why:* You cannot protect what you cannot see. With the list, you can match every item to a vulnerability database, such as the NVD, which publishes each new CVE with its severity and, when available, the fix. When the next big vulnerability is announced, you can answer "are we affected?" in minutes. In this demo, we want to show how an SBOM makes this possible, and that it can be scanned again later without the image.

**10. Store the images in a private registry and scan again:** We push the images to Harbor, which scans them and keeps the results in one place. We compare Harbor's results with our own scans. | *Why:* The registry is the gate between building and running, so it is the best place to check images and to enforce rules. In this demo, we want to show a central view of risk, and a second, independent scan to compare with our own.

**11. Sign the final image and enforce rules:** We sign the final image and its SBOM with Cosign, verify them, and set rules in the registry: no unsigned images, and no images with serious vulnerabilities. | *Why:* A signature shows who made the image and that nobody changed it, but it does not say the image is safe. So we combine it with the vulnerability check. In this demo, we want to show trust that you can prove: an image can run only if we know who made it and it passed our scan.

**12. Deploy to Kubernetes and expose to the public:** We deploy the signed image from Harbor with safe settings, check the Kubernetes files for mistakes, and make the application reachable from the internet. | *Why:* The same checks must work in a real cluster, and a new application should follow the same safe path from day one. In this demo, we want to prove the full path, from source code to a running service.

---