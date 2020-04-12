---
layout: post
title: How to achieve Mongo replication on Docker
date: 2020-04-05 18:44 +0100
---

# How to achieve Mongo replication on Docker
## Prologue
In the [previous post](2020-03-09-how-we-achieved-mongodb-replication.md), we showed how we used MongoDB replication to solve several problems we were facing before adopting it. Replication got to be a part of a bigger migration which brought stability, fault-tolerance and performance to our systems.


## Motivation
I noticed the lack of tutorials of setting up Mongo replication on Docker containers
and wanted to fill this gap along with some tests to see how a Mongo cluster behaves on specific scenarios.


## :checkered_flag: Objectives (Igual ao post anterior)
>To improve our production database and solve the identified limitations, our most clear objectives at this point were:
>- Upgrading Mongo v3.4 and v3.6 instances to v4.2 (all community edition)
>- Changing Mongo data backup strategy from **mongodump/mongorestore** to Mongo Replication
>- Merging Mongo containers into a single container and Mongo Docker volumes into a single volume

## Procedure steps (não soa muito bem :smile:)
1. prepare applications for Mongo connection string change
Needs change over time. When our applications were developed, there was no need to pass the Mongo connection URI through a variable, as most of the times Mongo was deployed as a microservice in the same stack as the application containers. With the centralization of Mongo databases, this change was introduced in the application code to update the variable on our CI/CD software whenever we need.

2. generate and deploy keyfiles
[MongoDB official documentation](https://docs.mongodb.com/manual/tutorial/enforce-keyfile-access-control-in-existing-replica-set/) has step-by-step instructions on out to setup Keyfile authentication on a Mongo Cluster. Using keyfile authentication enforces SSL Encryption on Transport Layer (**fontes?**).

```bash
openssl rand -base64 756 > <path-to-keyfile>
chmod 400 <path-to-keyfile>
```

The keyfile is passed through an argument on mongod command, as shown in the next step.

3. deploy existing containers with replSet argument

```bash
mongod --keyfile /keyfile --replSet=rs-myapp
```

4. define ports
As we had 4 apps in our production environment, we have defined hosts ports:
- 27017 for app 1
- 27018 for app 2
- 27019 for app 3
- 27020 for app 4

5. assemble a cluster composed of 3 servers in different datacenters and regions
6. plant 4 Mongo containers scaling to 3 on a Mongo cluster
7. extract 3 Mongo docker containers from main application server
8. extract another Mongo docker container from a minor application server
9. migrate backups and change which server they read the data
10. merge data from 4 Mongo docker containers into one database
11. unify backups
