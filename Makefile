default: vagrant-up

mitogen:
	ansible-playbook -c local mitogen.yml -vv

clean-nitrogen:
	rm -rf dist/
	rm *.retry


################################################################################
# CONFIGURATION
################################################################################
-include Makefile.local
#PROXY=http://<user>:<password>@<proxy_url>:<port>
VENVDIR=venv
INV=inventory/mycluster
KUBECTL=$(INV)/artifacts/kubectl.sh
KUBECFG=--kubeconfig $(INV)/artifacts/admin.conf
################################################################################

requirements:
	echo '[global]' > $(VENVDIR)/pip.conf
	echo 'proxy = $(PROXY)' >> $(VENVDIR)/pip.conf
	pip3 install -r requirements.txt

init-cluster: $(INV)

review-cluster: init-cluster
	@echo "===================== all.yml ========================"
	@cat $(INV)/group_vars/all/all.yml
	@echo "===================== k8s-cluster.yml ================"
	@cat $(INV)/group_vars/k8s-cluster/k8s-cluster.yml

$(INV):
	cp -rfp inventory/sample $@
	rm -f $@/hosts.ini

review:
	@echo "cat inventory/mycluster/group_vars/all/all.yml"
	@echo "cat inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml"

# Not to detroy your env you should use:
# See: https://linuxconfig.org/how-to-set-up-a-python-virtual-environment-on-debian-10-buster
# Completion:
# See: https://pip.pypa.io/en/stable/user_guide/#config-file
# PIP Proxy:
# See: https://pip.pypa.io/en/stable/user_guide/#config-file
python-env: /usr/bin/pyvenv /usr/bin/virtualenv
	#python3 -m venv $(CURDIR)
	[ -d $(VENVDIR) ] || virtualenv --python=/usr/bin/python3.7 $(VENVDIR)
	echo ". ~/.bashrc" > bashrc
	echo ". $(VENVDIR)/bin/activate" >> bashrc
	bash --rcfile $(CURDIR)/bashrc

/usr/bin/pyvenv:
	sudo apt install python3 python3-venv

/usr/bin/virtualenv:
	sudo apt install virtualenv python3-virtualenv

# check we are in virtualenv
testvenv:
	@[ ! -z "$(shell echo $$VIRTUAL_ENV)" ] || (echo "NOT in Python Vitualenv, Please run : make python-env" && exit 1)

vagrant-up: testvenv vagrant vagrant/config.rb init-cluster
	@echo "SETUP Proxy"
	[ -z '$(PROXY)' ] || sed -i -e 's!^# http_proxy:.*!http_proxy: \"$(PROXY)\"!' $(INV)/group_vars/all/all.yml
	[ -z '$(PROXY)' ] || sed -i -e 's!^# https_proxy:.*!https_proxy: \"$(PROXY)\"!' $(INV)/group_vars/all/all.yml
	# Addons
	make metrics
	make basic-auth
	make local-path-provisionner
	#make cephfs-provisioner
	#make registry
	make helm-addon
	#
	[ -z '$(PROXY)' ] || export https_proxy=$(PROXY) ; [ -z $(PROXY) ] || export http_proxy=$(PROXY) ; env | grep prox ; vagrant up


# See https://github.com/kubernetes-sigs/kubespray/blob/master/docs/ha-mode.md
# Defined by default, so not necessary to uncomment
# activate-nginx:
# 	@echo "Activate NGINX"
# 	sed -i -e 's!^# loadbalancer_apiserver_localhost: true!loadbalancer_apiserver_localhost: true!' $(INV)/group_vars/all/all.yml
# 	sed -i -e 's!^# loadbalancer_apiserver_type:!loadbalancer_apiserver_type:!' $(INV)/group_vars/all/all.yml
#
#
metrics:
	sed -i -e 's!^metrics_server_enabled:.*!metrics_server_enabled: true!' $(INV)/group_vars/k8s-cluster/addons.yml

basic-auth:
	sed -i -e 's!^# kube_basic_auth:.*!kube_basic_auth: true!' $(INV)/group_vars/k8s-cluster/k8s-cluster.yml

local-path-provisionner:
	sed -i -e 's!^local_path_provisioner_enabled:.*!local_path_provisioner_enabled: true!' $(INV)/group_vars/k8s-cluster/addons.yml

cephfs-provisioner:
	sed -i -e 's!^cephfs_provisioner_enabled:.*!cephfs_provisioner_enabled: true!' $(INV)/group_vars/k8s-cluster/addons.yml

registry:
	sed -i -e 's!^registry_enabled:.*!registry_enabled: true!' $(INV)/group_vars/k8s-cluster/addons.yml

helm-addon:
	sed -i -e 's!^helm_enabled:.*!helm_enabled: true!' $(INV)/group_vars/k8s-cluster/addons.yml

vagrant-down:
	vagrant destroy -f

vagrant:
	[ -d $@ ] || mkdir $@

vagrant/config.rb:
	#echo '$$instance_name_prefix = "kub"'	> $@
	#echo '$$vm_cpus = 1'			>> $@
	echo '$$vm_cpus = 2'			>> $@
	echo '$$vm_memory = 4096'		>> $@
	echo '$$num_instances = 3'		>> $@
	#echo '$$os = "centos-bento"'		>> $@
	#KK#echo '$$subnet = "10.10.1"'		>> $@
	#echo '$$network_plugin = "flannel"'	>> $@
	#echo '$$network_plugin = "calico"'	>> $@
	#echo '$$network_plugin = "weave"'	>> $@
	echo '$$inventory = "$(INV)"'		>> $@
	#echo '$$shared_folders = { 'temp/docker_rpms' => "/var/cache/yum/x86_64/7/docker-ce/packages" }' >> $@
	#echo '$$playbook = "facts.yml"'	>> $@
	echo '$$kube_node_instances_with_disks = true' >> $@
	echo '$$kube_node_instances_with_disks_size = "20G"' >> $@
	echo '$$kube_node_instances_with_disks_number = 2' >> $@
	echo '$$local_path_provisioner_enabled = true' >> $@

DEBUG=-vvv
DEBUG=
ansible: testvenv
	ansible-playbook $(DEBUG) -i $(INV)/vagrant_ansible_inventory  --become --become-user=root cluster.yml

TAGS=--tags=proxy,localhost,facts,always,cluster-roles
TAGS=--tags=proxy,proxydebug
TAGS=--tags=proxy,proxydebug,coredns,always
ansibletest: testvenv
	#[ -z '$(PROXY)' ] || export https_proxy=$(PROXY) ; [ -z $(PROXY) ] || export http_proxy=$(PROXY) ; 
		ansible-playbook $(DEBUG) -i $(INV)/vagrant_ansible_inventory  --become --become-user=root cluster.yml $(TAGS) --timeout=60

clean: vagrant-down
	rm -rf .vagrant
	rm -f vagrant/config.rb
	rm -rf $(INV)
	killall kubectl

infos:
	@echo "===== cluster-info ====="
	@$(KUBECTL) cluster-info
	@echo "===== get nodes  ====="
	@$(KUBECTL) get nodes
	@echo "===== get componentstatus ====="
	@$(KUBECTL) get componentstatus
	@echo "===== get all -n kube-system ====="
	@$(KUBECTL) get all -n kube-system
	@$(KUBECTL) get pods --all-namespaces

proxy:
	kubectl $(KUBECFG) proxy &

# Access to Dashboard
# https://github.com/kubernetes/dashboard/blob/master/docs/user/accessing-dashboard/1.7.x-and-above.md
dash: dashboard-token proxy dashboard-open

# See https://github.com/kubernetes-sigs/kubespray/blob/master/docs/vagrant.md
dashboard-token:
	kubectl $(KUBECFG) -n kube-system describe secret $(shell kubectl $(KUBECFG) -n kube-system get secret | grep kubernetes-dashboard | awk '{print $$1}')

pass=$(shell cat inventory/mycluster/credentials/kube_user.creds)
dashboard-open:
	@echo "===== Use user/passwd: kube/$(pass) ====="
	xdg-open http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/\#!/login

mito:
	[ -z '$(PROXY)' ] || export https_proxy=$(PROXY) ; [ -z $(PROXY) ] || export http_proxy=$(PROXY) ; ansible-playbook -c mycluster mitogen.yml -vv

# External tools k9s and popeye
runk9s: k9s
	./k9s -A $(KUBECFG)

runpop: popeye
	./popeye -A $(KUBECFG)

K9SURL=https://github.com/derailed/k9s/releases/download/v0.19.3/k9s_Linux_x86_64.tar.gz
k9s: k9s_Linux_x86_64.tar.gz
	tar xvzf k9s_Linux_x86_64.tar.gz $@

k9s_Linux_x86_64.tar.gz:
	https_proxy=$(PROXY) wget -O $@ $(K9URL)

POPURL=https://github.com/derailed/popeye/releases/download/v0.8.1/popeye_Linux_x86_64.tar.gz
popeye: popeye_Linux_x86_64.tar.gz
	tar xvzf  popeye_Linux_x86_64.tar.gz $@

popeye_Linux_x86_64.tar.gz:
	https_proxy=$(PROXY) wget -O $@ $(POPURL)

#HELMURL=https://get.helm.sh/helm-v3.2.0-linux-amd64.tar.gz
#helm: helm-v3.2.0-linux-amd64.tar.gz
#	tar xvzf helm-v3.2.0-linux-amd64.tar.gz linux-amd64/helm
#	mv linux-amd64/helm helm
#	rmdir linux-amd64
#
helm: /snap/bin/helm
/snap/bin/helm:
	sudo snap install helm --classic

helmlist:
	helm --kubeconfig $(INV)/artifacts/admin.conf list

helmlisthub:
	https_proxy=$(PROXY) helm search hub

helm-v3.2.0-linux-amd64.tar.gz:
	https_proxy=$(PROXY) wget -O $@ $(HELMURL)

# ssh to nodes
$(INV)/ssh-config:
	[ -f $(INV)/ssh-config ] || vagrant ssh-config > $(INV)/ssh-config

ssh%: $(INV)/ssh-config
	ssh -F $< k8s-$*

linkconf:
	[ -f ~/.kube/config ] || [ ! -f ~/.kube/config ] || mv ~/.kube/config ~/.kube/config.sos
	[ -L ~/.kube/config ] || ln -s $(CURDIR)/$(INV)/artifacts/admin.conf ~/.kube/config
