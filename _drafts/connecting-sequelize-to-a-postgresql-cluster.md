---
layout: post
title: Connecting Sequelize to a PostgreSQL cluster
---
:large_blue_diamond: :elephant: :sheep:

## Prologue

In the [previous post][1] we showed how to automate a PostgreSQL fault-tolerant cluster with Vagrant and Ansible.

This kind of setup makes our database cluster resilient to server failure and keeps the data available with no need for human interaction

## Objectives
- connecting a **NodeJS** application with **Sequelize** to a **PostgreSQL** cluster in order to write from primary and read from standby nodes;
- create and assign a **Digital Ocean Floating IP** (aka FLIP) to our current primary database node;
- interact with **Digital Ocean CLI** to reassign FLIP to new primary node;
- keep this switchover transparent to the **NodeJS** application, so the whole system works without human help.

## Pre-requisites
- **PostgreSQL** cluster with **repmgr** (you can follow the [tutorial][1] or just use a cluster with streaming replication and simulate failure + manual promotion)
- **Digital Ocean** account and API token ([create an account][2])
- [NodeJS][3] and [npm][4] installed (I'm using NodeJS v12 with npm v6)

## NodeJS application

## Normal situation test

## Digital Ocean CLI configuration

## Add script to repmgr promote command

## Primary failure test

[1]: https://blog.jscrambler.com/how-to-automate-postgresql-and-repmgr-on-vagrant/
[2]: https://m.do.co/c/x
[3]: https://nodejs.org/en/download/
[4]: https://www.npmjs.com/
