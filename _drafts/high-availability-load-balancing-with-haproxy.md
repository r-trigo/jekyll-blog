---
layout: post
title: High Availability HAProxy Load Balancing
tags: haproxy high availability cluster, haproxy high availability setup, keepalived logs, keepalived nginx, keepalived vs haproxy, keepalived load balancing
---
:scales: :scales: :up:

## Prologue
In previous posts we have been writing about high availability on databases, like [MongoDB][1] and [PostgreSQL][2].

So, if we have a load balancer forwarding web requests to an application which accesses a highly available database is more resilient than a vulnerable single instance database. Okay. And if your load balancer stops working, that HA database might still store your data safely, but can't get your clients to reach it.

That's why we are now about to learn how to build a highly available load balancer chain with [HAProxy][3] and [keepalived][4] on DigitalOcean, with the help of Floating IP.

## Objectives
- create and assign a **Digital Ocean Floating IP** (aka FLIP) to our current primary load balancer node;
- setting up an **Apache** web server with several virtual servers
- configure 2 **HAProxy** nodes (master and backup) ready to serve the Apache sites
- add **keepalived** to watch **HAProxy** process and establish high availability
- make **keepalived** interact with **Digital Ocean CLI** to reassign FLIP to new primary node on promotions;
- keep this switchover transparent to the **Apache** clients, so the whole system works without human help.

## Prerequisites
- a **Digital Ocean** account and API token ([create an account using my referral to get free credits][5])

## Set up your cluster

### Create your droplets
![jscrambler-blog-connecting-sequelize-to-postgresql-cluster-create-droplet](https://blog.jscrambler.com/content/images/2020/08/jscrambler-blog-connecting-sequelize-to-postgresql-cluster-create-droplet.png)

Create 3 droplets, preferably with the Ubuntu 20.04 operating system:
- web (Apache server)
- haproxy-1 (master HAProxy)
- haproxy-2 (backup HAProxy)

To make configurations run smoother, add your public SSH key when creating the droplets. You can also use the key pair I provided on [GitHub][6] for testing purposes.

*Note: If you use an SSH private key which is shared publicly on the internet, your cluster can get hacked.*

![create-3-droplets-2](../assets/images/create-3-droplets-2.png)

### Assign a floating IP to your primary node
Create a floating IP address and assign it to your primary node (haproxy-1).
![assign-floating-ip-2](../assets/images/assign-floating-ip-2.png)


### Install Apache server
Let's start with the web server. We're going with Apache, making use of its VirtualHost feature to simulate several virtual machines with similar web servers. Later, the traffic will be forwarded by the load balancer to these different servers (virtual hosts) and they will respond with the message `Backend <number>`, with number being the virtual hosts identifying number, a value between 1 and 7. Clone the repo in the VM to copy the Apache configuration files (**.conf**).

```bash
# it is useful to clone this repo in the server
git clone cenas...

apt-get update
apt-get install -y apache2
a2enmod headers
a2dissite 000-default
# go to this repo
cd <repo_path>/apache/configs
for x in site-*.conf; do
  cp ${x} /etc/apache2/sites-available
  a2ensite ${x%.*}
done
cp site-*.conf /etc/apache2/sites-available
cp ports.conf /etc/apache2/
cp apache2.conf /etc/apache2
service apache2 restart
touch /var/www/html/haproxy_check
```

### Install HAProxy
Next, we install HAProxy on the load balancing nodes (**haproxy-1** and **haproxy-2**). Clone and copy the HAProxy configuration and scripts files. HAProxy will serve the web pages from port 8001 to 8007 (matching Apache virtual hosts 1 to 7). The HAProxy stats page will be served from port 8101 to 8107 the same way.

```bash
# it is useful to clone this repo in the server
git clone cenas...

apt-get update
apt-get install -y haproxy
# go to this repo
cd <repo_path>/haproxy/configs
cp haproxy.cfg /etc/haproxy/
cp rsyslog.conf /etc/
mkdir -p /opt/scripts
cd <repo_path>/apache/scripts
cp reassign-hcloud-flip.sh /opt/scripts/
chmod u+x /opt/scripts/reassign-hcloud-flip.sh
service rsyslog restart
service haproxy restart
```

#### Configure HAProxy
/etc/haproxy/haproxy.cfg

### Install keepalived
Keepalived is a tool that will watch our HAProxy process ID in the operating system. The keepalived installation in **haproxy-1** will communicate periodically with **haproxy-2** keepalived. If the master keepalived detects a HAProxy failure, it will order the keepalived in the backup node (haproxy-2) to enable HAProxy in that node and triggers the promotion script we wrote. This script will send an alert to a Slack channel through a webhook.

Install keepalived in **haproxy-1** and **haproxy-2** and copy the respective configuration file.

```bash
apt-get install -y keepalived
# for haproxy-1 copy keepalived_master.conf
cp /vagrant/configs/keepalived_master.conf /etc/keepalived/keepalived.conf
# for haproxy-2 copy keepalived_backup.conf
cp /vagrant/configs/keepalived_backup.conf /etc/keepalived/keepalived.conf
service keepalived restart
```

#### Configure keepalived
/etc/keepalived/keepalived.conf

## Primary failure test
- stop haproxy on haproxy-1
- test Apache site

## Reverting the promotion
- fix haproxy-1
- stop keepalived on haproxy-2

## Conclusion
- vagrant file for GitHub
- if there is no load balancer available, it does not matter how many application and database servers you have to handle the load

[You can find the source code in this post on GitHub][99].

[1]: https://blog.jscrambler.com/how-to-achieve-mongo-replication-on-docker/
[2]: https://blog.jscrambler.com/how-to-automate-postgresql-and-repmgr-on-vagrant/
[3]: http://www.haproxy.org/
[4]: https://keepalived.org/
[5]: https://m.do.co/c/00ac35d4c268
[6]: https://github.com/r-trigo/postgres-repmgr-vagrant/tree/master/provisioning/roles/ssh/files/keys
[99]: https://github.com/r-trigo
