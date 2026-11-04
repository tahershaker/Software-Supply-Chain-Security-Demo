# Software Supply Chain Security Demo

> See software supply chain security in action. We follow one small web application from its source code to a running service. We check the code, package it, find and fix its vulnerabilities, move to hardened images to shrink the attack surface, then sign it, store it in a private registry and run it on Kubernetes. Everything runs on an environment that we build on AWS.


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
4. We switch to a **hardened image** based on `chainguard` images. Before we use it, we check who built it: we verify its signature and read its SBOM (a list of everything inside the image). Then we build and scan again.
5. We reduce the attack surface further with a **multi-stage build**. We build the application in a development image, `chainguard -dev` images, and we run it in a minimal, distroless image. We scan and compare all the results.
6. We run the final image as a standalone container.
7. We create SBOMs, store all the images in a private registry that scans images, sign the final image, and set rules that block images that are not safe.
8. We deploy the final image to a Kubernetes cluster and expose it to the public.

The application and the exercise come from a `chainguard` repository. It contains a small web application written in Go, and its libraries have known vulnerabilities. To understand the exercise in more detail, please check this repository: [chainguard-technical-challenge](https://github.com/maligin/chainguard-technical-challenge).

For the hardened images, we use the container images from `Chainguard`. We compare them with the open-source images, to see what a hardened base changes.

To do all this in a realistic setting, we also build an environment on AWS using a Terraform script. The Terraform script creates a private and a public network, one work machine (the `bastion`), and a small Kubernetes cluster with three nodes (one `master` node and two `worker` nodes) running `RKE2`. A load balancer is the public entry point. On the cluster, we install Harbor, an open-source private registry, and later we deploy the application. You can find more details in the [Infrastructure](#infrastructure) section.

> **Do not use in production.** This is a demo for learning. The environment is simple on purpose, and some settings (for example, skipping certificate checks for a private registry) are not safe for a real production system.

---

## Strategy

> **The idea in one sentence**

We check the code first, then we find out where the vulnerabilities come from, remove them in steps, scan after every step, and prove that the final image can be trusted.

### Why we start with the code: shift left

Think of the path of an application as a line from left to right. We write the code, we build it, we package it into an image, we store the image, and we run it. The "left" is the start of this line.

If you find a security problem at the left, it is cheap to fix. You change a line of code or update a library, and you move on. If you find the same problem at the right, in production, it is expensive. The image is built, stored and running, and you must stop, fix, build, test and deploy again. So modern teams **shift left**. This means they check security as early as possible. This idea is part of **DevSecOps**.

This is why we start with the code, and not with an image.

### What do we check in the code?

We check two things.

1. **SAST** (Static Application Security Testing). A SAST tool reads our own source code and looks for risky patterns, such as weak settings or unsafe functions.
2. **SCA** (Software Composition Analysis). An SCA tool looks at the libraries we use and compares them with a database of known vulnerabilities.

Our application is very small, so there is almost no code of our own to check. Most of the risk is in the libraries. A SAST tool alone would miss this. This is why we use both kinds of check.

### What happens in a real pipeline, and what we do here

In a real company, the code goes through a CI/CD pipeline. The first jobs of the pipeline scan, check and test the code. If a check fails, the pipeline stops, and the image is never built.

In this demo, we do something different on purpose. We check the code, we see the problems, and then we **build anyway**. The reason is learning. We want to see what the same problems look like inside an image, and which new problems the image adds, for example the ones that come from the base image. After that, we fix everything and build again, so you can see the difference.

### Where do vulnerabilities come from?

A container image is made of layers, and each layer comes from a different place. For our Go application, a vulnerability can come from four places:

1. **Our own code.** The few lines we wrote. SAST checks this part.
2. **The libraries.** These are the libraries listed in the `go.mod` file, such as the Gin web framework. SCA checks this part.
3. **Go itself.** A Go program carries a part of the Go standard library inside its binary. If we build with an old Go version, we also carry the old bugs.
4. **The base image.** This is the Linux system inside the image, for example Debian. It has many packages, and each package can have bugs.

When we scan an image, the scanner tells us the type of each finding (operating system package, Go library, Go standard library). So even when we change several things at once, we can still see which part each change helped.

### The images we build

We build four images. They tell the story in order, and we change one thing at a time where we can.

| Image | Code and libraries | Go | Base image | Build style | What it shows |
|:---|:---|:---|:---|:---|:---|
| `hello-oss-single-v1` | Original | 1.18 (old) | Old open-source Go image | Single-stage | The starting point: problems from the code, the libraries, Go and the base image. |
| `hello-oss-single-v2` | Fixed | Current | Current open-source Go image | Single-stage | What fixing the code, the libraries and the image gives us. |
| `hello-cg-single` | Fixed | Current | Hardened Go development image | Single-stage | What changes when only the base image changes. |
| `hello-cg-multi` | Fixed | Current | Hardened Go development image to build, hardened minimal image to run | Multi-stage | What changes when only the build style changes. |

Look at the pairs. Between `v2` and `cg-single`, the only change is the base image. Between `cg-single` and `cg-multi`, the only change is the build style. This is why the comparisons are fair.

### Why a hardened image?

After we fix our code and update everything, some findings will remain in the open-source image. We cannot fix them by updating, for example because no fix exists yet. So what can we do?

We can reduce how much is in the image. Every package in an image is a possible vulnerability. If our application needs only one file to run, why should the image carry a shell, a package manager and hundreds of tools? A hardened image has only what the application needs. This makes the attack surface small. It also means fewer findings and less patching work.

A hardened single-stage image will improve the CVE count, but some CVEs can remain, because it still carries the build tools. The next step is to remove them.

### Why a multi-stage build?

A single-stage image builds and runs the application in the same image. So the compiler and the build tools travel to production, and the application does not need them to run.

A **multi-stage** build splits the work. The first stage is a development image. It has the compiler and the tools, and it builds the application. The last stage is a minimal, distroless image. It has almost nothing in it. We copy only the finished application into it, and we change nothing else. The final image has no compiler, no shell and no package manager, so the attack surface is much smaller.

### Check before you use: who built this image?

Before we use an image that someone else built, we should ask three questions. Who built it? Was it changed on the way? What is inside it? The hardened images are signed, and they publish an SBOM. So before every hardened build, we pull the image, check the signature with Cosign, and read its SBOM. Only then do we build. We also pin the image by its digest, which is a fingerprint, so we build on exactly the image that we checked.

### Four stages for the work

We do the work in four stages.

* **Stage 1: the code.** We check the code and the libraries before we build.
* **Stage 2: the images, with standard tools on the bastion.** We use command-line tools to build, scan, run and create SBOMs. Anyone can repeat the work with them.
* **Stage 3: the registry.** We move the images to Harbor. Harbor scans images, stores SBOMs and signatures, and can block images that break our rules. After that, we compare the Harbor results with the Stage 2 results.
* **Stage 4: the cluster.** We deploy the final image to Kubernetes and expose it to the public.

## How we read the results

* **Two scanners, not one.** Scanners use different databases and different rules, so they can give different numbers. We use two and compare them.
* **Reachability.** A scanner lists everything that is installed. It does not say if the program really uses the vulnerable code. We use a Go tool to check this, so we can tell which findings matter most.
* **Fixable or not.** For every finding, we ask: is there a fixed version? If yes, we update. If no, we cannot fix it by updating, and we must think about removing the package or using a smaller image.
* **Evidence.** We save the raw scan files, the date of each scan, and the version of each tool. Vulnerability data changes every day, so numbers can differ from one day to the next. Saved evidence lets us explain our numbers later.

### The tools and why we use them

| Tool | What it does | Why we use it |
|:---|:---|:---|
| **Terraform** | Creates the AWS environment from code. | The environment is repeatable. Anyone can create it again with a few commands. |
| **AWS** (VPC, EC2, load balancer) | Network, servers and the public entry point. | A realistic cloud setting with a public and a private network. |
| **RKE2** | An open-source Kubernetes distribution. | Simple to install, secure by default, and a good fit for a small cluster. |
| **kubectl** and **Helm** | Talk to Kubernetes, and install packaged applications. | The standard way to manage a cluster and to install Harbor. |
| **local-path-provisioner** | Gives the cluster simple disk storage on the nodes. | Harbor needs disk space to store images. |
| **Ingress controller** | One entry door for web traffic into the cluster. | Harbor and our application can share one public entry point. |
| **Harbor** | Open-source private container registry. | It stores images, scans them, shows SBOMs and signatures, and can enforce rules. |
| **gosec** | SAST tool for Go. Reads our code and warns about risky patterns. | Checks our own code before we build. |
| **govulncheck** | Official Go tool. Checks if vulnerable code is really used. | It separates findings that matter from findings that are only listed. |
| **Trivy** | Open-source scanner for code, images and Kubernetes files. | Checks libraries in the code, scans images, and checks our Kubernetes files. Harbor uses Trivy too, so we can compare. |
| **Grype** | Open-source vulnerability scanner. | The second scanner for images. It can also scan an SBOM without the image. |
| **Docker** | Builds and runs container images. | The most common tool for this work, and it works the same everywhere. |
| **Hadolint** | Checks a Dockerfile for common mistakes. | Catches bad habits before we build. |
| **Syft** | Creates an SBOM from an image. | An SBOM tells us exactly what is inside an image. |
| **Cosign** | Signs and verifies images and SBOMs. | We use it to check the signature and the SBOM of the hardened images before we use them, and to sign our own final image. |
| **jq** | Reads and filters JSON files. | Scan results are JSON, and jq helps us count and compare them. |

---
