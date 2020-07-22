---
layout: post
title: How to build a fault tolerant PostgreSQL cluster
---
:elephant: :collision: :ok_hand:

I often get asked if it's possible to build a resilient system with PostgreSQL.

Considering that resilience should feature cluster high-availability, fault tolerance, and self-healing, it's not an easy answer. But there is a lot to be said about this.

As of today, we can't achieve that level of resilience with the same ease as MongoDB built-in features. But let's see what we can in fact do with the help of **repmgr** and some other tooling.

At the end of this exercise, we will have achieved some things that come in handy, such as:
- a few Ansible roles that can be reused for production
- a Vagrantfile for single-command cluster deployment
- a development environment that’s more realistic; being close to production state is good to foresee "production-exclusive issues"

## Objectives
- build a local development environment PostgreSQL cluster with fault tolerance capabilities;
- develop configuration management code to reuse in production.

## Pre-requisites

Install [Vagrant][1], [VirtualBox][2] and [Ansible][3]
```bash
sudo apt install vagrant
sudo apt install virtualbox && sudo apt install virtualbox-dkms
sudo apt install ansible
```

**Note**: An alternative to installing Ansible on your host machine would be using the `ansible-local` Vagrant provider, which needs Ansible installed on the generated virtual machine instead.

## Configuration
### 1. Write a Vagrantfile

You can use `vagrant init` to generate the file or simply create it and insert our first blocks.

```ruby
Vagrant.configure("2") do |config|
  (1..3).each do |n|
    config.vm.define "node#{n}" do |define|
      define.ssh.insert_key = false
      define.vm.box = "ubuntu/bionic64"
      define.vm.hostname = "node#{n}"
      define.vm.network :private_network, ip: "172.16.1.1#{n}"

      define.vm.provider :virtualbox do |v|
        v.cpus = 2
        v.memory = 1024
        v.name = "node#{n}"
      end
    end
  end
end
```

Let's go block by block:
  - the 1st block is where we set up the Vagrant version;
  - on the 2nd block, we iterate the following code so we reuse it to generate 3 equal VMs;
  - OS, hostname and network settings are set in the 3rd block;
  - the 4th block contains VirtualBox specific settings.

You can create the servers with:
```bash
# create all 3 VMs
vagrant up
# or create only a specific VM
vagrant up node1
```

### 2. Add a provisioner

Just by doing the first step alone, we can already launch 3 working virtual machines. A little exciting, but the best is yet to come.

Launching virtual machines is a nice feature of Vagrant, but we want these servers to have **PostgreSQL** and **repmgr** configured, so we will use configuration management software to help us. This is the moment **Ansible** walks in to amaze us.

Vagrant supports several providers, two of them being [Ansible][4] and [Ansible Local][5]. The difference between them is where Ansible runs, or in other words, where it must be installed. By Vagrant terms, the Ansible provider runs on a host machine (your computer) and the Ansible Local provider runs on guest machines (virtual machines). As we already installed Ansible in the prerequisites section, we'll go with the first option.

Let's add a block for this provisioner in our `Vagrantfile`.

```ruby
Vagrant.configure("2") do |config|
  (1..3).each do |n|
    config.vm.define "node#{n}" do |define|
      define.ssh.insert_key = false
      define.vm.box = "ubuntu/bionic64"
      define.vm.hostname = "node#{n}"
      define.vm.network :private_network, ip: "172.16.1.1#{n}"

      define.vm.provider :virtualbox do |v|
        v.cpus = 2
        v.memory = 1024
        v.name = "node#{n}"
      end

      if n == 3
        define.vm.provision :ansible do |ansible|
          ansible.limit = "all"
          ansible.playbook = "provisioning/playbook.yaml"

          ansible.host_vars = {
            "node1" => {:connection_host => "172.16.1.11",
                        :node_id => 1,
                        :role => "primary" },

            "node2" => {:connection_host => "172.16.1.12",
                        :node_id => 2,
                        :role => "standby" },

            "node3" => {:connection_host => "172.16.1.13",
                        :node_id => 3,
                        :role => "witness" }
          }
        end
      end

    end
  end
end
```

**Ansible** allows us to configure several servers simultaneously. To take advantage of this feature on **Vagrant**, we add `ansible.limit = "all"` and must wait until all 3 VMs are up. **Vagrant** knows they are all created because of the condition `if n == 3`, which makes **Ansible** only run after **Vagrant** iterated 3 times.

`ansible.playbook` is the configuration entry point and `ansible.host_vars` contains the **Ansible** host variables to be used on the tasks and templates we are about to create.

### 3. Create an organized Ansible folder structure

If you're already familiar with **Ansible**, there's little to learn in this section. For those who aren't, it doesn't get too complicated.

First, we have a folder for all Ansible files, named `provisioning`. Inside this folder, we have our aforementioned entry point `playbook.yaml`, a `group_vars` folder for **Ansible** group variables, and a `roles` folder.

We could have all **Ansible** tasks within `playbook.yaml`, but role folder structure helps with organization. You can read the [Ansible documentation][6] to learn the best practices. Below, you will find the folder structure for this tutorial.

```bash
project_root
| provisioning
|  |  group_vars
|  |  |  all.yaml
|  |  roles
|  |  |  postgres_12
|  |  |  registration
|  |  |  repmgr
|  |  |  ssh
|  |  playbook.yaml
|  Vagrantfile
```

### 4. Ansible roles
#### 4.1 PostgreSQL role
To configure `repmgr` on PostgreSQL, we need to edit two well-known PostgreSQL configuration files: `postgresql.conf` and `pg_hba.conf`. We will then write our tasks to apply the configurations on `tasks/main.yaml`. I named the PostgreSQL role folder as `postgres_12` but you can easily use another version if you want to.

```
postgres_12
|  tasks
|  |  main.yaml
|  templates
|  |  pg_hba.conf.j2
|  |  pg_hba.conf.j2
```

You can reuse the default file which comes with PostgreSQL installation and add the following lines to whitelist `repmgr` database sessions from your trusted VMs. Create an Ansible template file ([Jinja2 format][7]) like so:

```jinja
# default configuration (...)

# repmgr
local   replication   repmgr                              trust
host    replication   repmgr      127.0.0.1/32            trust
host    replication   repmgr      {{ node1_ip }}/32       trust
host    replication   repmgr      {{ node2_ip }}/32       trust
host    replication   repmgr      {{ node3_ip }}/32       trust

local   repmgr        repmgr                              trust
host    repmgr        repmgr      127.0.0.1/32            trust
host    repmgr        repmgr      {{ node1_ip }}/32       trust
host    repmgr        repmgr      {{ node2_ip }}/32       trust
host    repmgr        repmgr      {{ node3_ip }}/32       trust
```

In the same fashion as `pg_hba.conf`, you can reuse the `postgresql.conf` default file and add a few more replication related settings to the bottom of the file:

```jinja
# default configuration (...)

# repmgr
listen_addresses = '*'
shared_preload_libraries = 'repmgr'
wal_level = replica
max_wal_senders = 5
wal_keep_segments = 64
max_replication_slots = 5
hot_standby = on
wal_log_hints = on
```

The tasks below will install PostgreSQL and apply our configurations. Their names are self-explanatory.

```yaml
- name: Add PostgreSQL apt key
  apt_key:
    url: https://www.postgresql.org/media/keys/ACCC4CF8.asc

- name: Add PostgreSQL repository
  apt_repository:
    # ansible_distribution_release = xenial, bionic, focal
    repo: deb http://apt.postgresql.org/pub/repos/apt/ {{ ansible_distribution_release }}-pgdg main

- name: Install PostgreSQL 12
  apt:
    name: postgresql-12
    update_cache: yes

- name: Copy database configuration
  template:
    src: full_postgresql.conf.j2
    dest: /etc/postgresql/12/main/postgresql.conf
    group: postgres
    mode: '0644'
    owner: postgres

- name: Copy user access configuration
  template:
    src: pg_hba.conf.j2
    dest: /etc/postgresql/12/main/pg_hba.conf
    group: postgres
    mode: '0640'
    owner: postgres
```

#### 4.2 SSH server configuration

```
ssh
|  files
|  |  keys
|  |   |  id_rsa
|  |   |  id_rsa.pub
|  tasks
|  |  main.yaml
```

Generate a key pair to use throughout our virtual machines to allow access to them. If you don't know how to do it, [this link can help][8]. Just make sure the keys file paths match the paths in the next step.

The tasks below will install the OpenSSH server and apply our configurations. Their names are self-explanatory.

```yaml
- name: Install OpenSSH
  apt:
    name: openssh-server
    update_cache: yes
    state: present

- name: Create postgres SSH directory
  file:
    mode: '0755'
    owner: postgres
    group: postgres
    path: /var/lib/postgresql/.ssh/
    state: directory

- name: Copy SSH private key
  copy:
    src: "keys/id_rsa"
    dest: /var/lib/postgresql/.ssh/id_rsa
    owner: postgres
    group: postgres
    mode: '0600'

- name: Copy SSH public key
  copy:
    src: "keys/id_rsa.pub"
    dest: /var/lib/postgresql/.ssh/id_rsa.pub
    owner: postgres
    group: postgres
    mode: '0644'

- name: Add key to authorized keys file
  authorized_key:
    user: postgres
    state: present
    key: "{{ lookup('file', 'keys/id_rsa.pub') }}"

- name: Restart SSH service
  service:
    name: sshd
    enabled: yes
    state: restarted
```

#### 4.3 repmgr installation

```
repmgr
|  tasks
|  |  main.yaml
|  templates
|  |  repmgr.conf.j2
```

We configure settings like promote command, follow command, timeouts and retry count on failure scenarios inside `repmgr.conf`. We will copy this file to its default directory `/etc` to avoid passing the `-f` argument on the `repmgr` command all the time.

The tasks below will install `repmgr` and apply our configurations. Their names are self-explanatory.

```yaml
- name: Download repmgr repository installer
  get_url:
    dest: /tmp/repmgr-installer.sh
    mode: 0700
    url: https://dl.2ndquadrant.com/default/release/get/deb

- name: Execute repmgr repository installer
  shell: /tmp/repmgr-installer.sh

- name: Install repmgr for PostgreSQL {{ pg_version }}
  apt:
    name: postgresql-{{ pg_version }}-repmgr
    update_cache: yes

- name: Setup repmgr user and database
  become_user: postgres
  ignore_errors: yes
  shell: |
    createuser --replication --createdb --createrole --superuser repmgr &&
    psql -c 'ALTER USER repmgr SET search_path TO repmgr_test, "$user", public;' &&
    createdb repmgr --owner=repmgr

- name: Copy repmgr configuration
  template:
    src: repmgr.conf.j2
    dest: /etc/repmgr.conf

- name: Restart PostgreSQL
  systemd:
    name: postgresql
    enabled: yes
    state: restarted

```

#### 4.4 repmgr node registration
Finally, we reach the moment where fault tolerance is established.

```
registration
|  tasks
|  |  main.yaml
```

```yaml
node_id = {{ node_id }}
node_name = 'node{{ node_id }}'
conninfo = 'host={{ connection_host }} user=repmgr dbname=repmgr'
data_directory = '/var/lib/postgresql/{{ pg_version }}/main'
use_replication_slots = yes
reconnect_attempts = 5
reconnect_interval = 1
failover = automatic
pg_bindir = '/usr/lib/postgresql/{{ pg_version }}/bin'
promote_command = 'repmgr standby promote -f /etc/repmgr.conf'
follow_command = 'repmgr standby follow -f /etc/repmgr.conf'
log_level = INFO
log_file = '/var/log/postgresql/repmgr.log'
```

This role was built according to the `repmgr` documentation and it might be the most complex role, as it needs to:
- run some commands as root and others as Postgres;
- stop services between reconfigurations;
- have different tasks for primary, standby, and support [witness][9] role configuration, in case you want to have witnesses in your cluster (just assign `role: witness`)

```yaml
- name: Register primary node
  become_user: postgres
  shell: repmgr primary register
  ignore_errors: yes
  when: role == "primary"

- name: Stop PostgreSQL
  systemd:
    name: postgresql
    state: stopped
  when: role == "standby"

- name: Clean up PostgreSQL data directory
  become_user: postgres
  file:
    path: /var/lib/postgresql/{{ pg_version }}/main
    force: yes
    state: absent
  when: role == "standby"

- name: Clone primary node data
  become_user: postgres
  shell: repmgr -h {{ node1_ip }} -U repmgr -d repmgr standby clone
  ignore_errors: yes
  when: role == "standby"

- name: Start PostgreSQL
  systemd:
    name: postgresql
    state: started
  when: role == "standby"

- name: Register {{ role }} node
  become_user: postgres
  shell: repmgr {{ role }} register -F
  ignore_errors: yes
  when: role != "primary"

- name: Start repmgrd
  become_user: postgres
  shell: repmgrd
  ignore_errors: yes
```

## 5. Set group variables
Create a file `group_vars/all.yaml` to set your VMs IP addresses and the PostgreSQL version you would like to use. Like `host_vars` set on `Vagrantfile`, these variables will be placed in the templates placeholders.

```yaml
client_ip: "172.16.1.1"
node1_ip: "172.16.1.11"
node2_ip: "172.16.1.12"
node3_ip: "172.16.1.13"
pg_version: "12"
```

## 6. Put all pieces together with a playbook
The only thing missing is the playbook itself. Create a file named `playbook.yaml` and invoke the roles we have been developing. `gather_facts` is an **Ansible** property to fetch operative system data like distribution (`ansible_distribution_release`) among other useful variables. You can also read these variables with the [Ansible setup module][10].

```yaml
- hosts: all
  gather_facts: yes
  become: yes
  roles:
    - postgres_12
    - ssh
    - repmgr
    - registration
```

## 7. Start cluster
It's finished. You can now start your cluster with `vagrant up` and then perform your connections and failover tests.

## Testing cluster failover

Now that our cluster is up and configured, you can start by shutting down your standby node:
```bash
# save standby state and shut it down ungracefully
vagrant suspend node2
```
You will see that the cluster is operating normally. Bring the standby node back and it will stay that way.
```bash
# bring standby back online after suspension
vagrant resume node1
```
How about taking down the primary node?
```bash
# save primary state and shut it down ungracefully
vagrant suspend node1
```

At this point, as `repmgrd` is enabled, the standby node will retry connecting to the primary node the configured number of times (`reconnect_attempts = 5`) and, if it obtains no response, will promote itself to primary and take over write operations on the PostgreSQL cluster. Success!

To join the cluster again, the old primary node will have to lose its current data, clone the new primary data, and register as a new standby.

```bash
vagrant resume node1
vagrant ssh node1
service postgresql stop
rm -r /var/lib/postgresql/12/main
repmgr -h 172.16.1.12 -U -d repmgr standby clone
service postgresql start
repmgr standby register -F
repmgrd
repmgr service status
```

This last command shows us that the cluster is working properly, but with inverted roles.
```bash
postgres@node1:~$ repmgr service status
 ID | Name  | Role    | Status    | Upstream | repmgrd | PID   | Paused? | Upstream last seen
----+-------+---------+-----------+----------+---------+-------+---------+--------------------
 1  | node1 | primary | * running |          | running | 22490 | no      | n/a                
 2  | node2 | standby |   running | node1    | running | 22548 | no      | 0 second(s) ago   
 3  | node3 | witness | * running | node1    | running | 22535 | no      | 0 second(s) ago   
```
Nothing wrong with this, but let's see [how to make these nodes switch their roles][11].

```bash
# ssh in and out just to add host key to known_hosts file
ssh <current_primary_ip_address> -o StrictHostKeyChecking=no
# trigger switchover on current standby
repmgr standby switchover --siblings-follow
```

And we're back to the initial state.

# Conclusion

We managed to build a fault-tolerant PostgreSQL cluster using **Vagrant** and **Ansible**.

High availability is a big challenge. Much like life’s own matters, we are only prepared for the biggest challenges when we fit that challenges’ conditions.

Production environment unique problems are natural and tough to guess. Bridging the gap between development and production is a way to prevent deployment/production issues. We can make some efforts toward that objective, and that is precisely what we just achieved with this high availability database setup.

[You can find the source code here][12]

[1]: https://www.vagrantup.com/
[2]: https://www.virtualbox.org/
[3]: https://www.ansible.com/
[4]: https://www.vagrantup.com/docs/provisioning/ansible.html
[5]: https://www.vagrantup.com/docs/provisioning/ansible_local
[6]: https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html#directory-layout
[7]: https://docs.ansible.com/ansible/latest/user_guide/playbooks_templating.html
[8]: https://docs.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#generating-a-new-ssh-key
[9]: https://repmgr.org/docs/current/repmgr-witness-register.html
[10]: https://docs.ansible.com/ansible/latest/modules/setup_module.html
[11]: https://repmgr.org/docs/current/repmgr-standby-switchover.html
[12]: https://github.com/r-trigo/postgres-repmgr-vagrant
