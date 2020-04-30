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
KUBECONFIG=$(INV)/kubeconfig
KUBEOPT=--kubeconfig=$(KUBECONFIG)
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
	#
	[ -z '$(PROXY)' ] || export https_proxy=$(PROXY) ; [ -z $(PROXY) ] || export http_proxy=$(PROXY) ; env | grep prox ; vagrant up
	make get-kubeconf


activate-nginx:
	@echo "Activate NGINX"
	sed -i -e 's!^# loadbalancer_apiserver_localhost: true!loadbalancer_apiserver_localhost: true!' $(INV)/group_vars/all/all.yml
	sed -i -e 's!^# loadbalancer_apiserver_type:!loadbalancer_apiserver_type:!' $(INV)/group_vars/all/all.yml


vagrant-down:
	vagrant destroy -f

vagrant:
	[ -d $@ ] || mkdir $@

vagrant/config.rb:
	#echo '$$instance_name_prefix = "kub"'	> $@
	#echo '$$vm_cpus = 1'			>> $@
	echo '$$vm_cpus = 2'			>> $@
	echo '$$num_instances = 3'		>> $@
	#echo '$$os = "centos-bento"'		>> $@
	#KK#echo '$$subnet = "10.10.1"'		>> $@
	#echo '$$network_plugin = "flannel"'	>> $@
	#echo '$$network_plugin = "calico"'	>> $@
	#echo '$$network_plugin = "weave"'	>> $@
	echo '$$inventory = "$(INV)"'		>> $@
	#echo '$$shared_folders = { 'temp/docker_rpms' => "/var/cache/yum/x86_64/7/docker-ce/packages" }' >> $@
	#echo '$$playbook = "facts.yml"'	>> $@

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
	rm -f ssh-config $(INV)/kubeconfig
	killall kubectl

get-kubeconf:
	[ -f $(INV)/ssh-config ] || vagrant ssh-config > $(INV)/ssh-config
	[ -e $(INV)/kubeconfig ] || ssh -F $(INV)/ssh-config k8s-1 "sudo cat /etc/kubernetes/admin.conf" > $(KUBECONFIG)

infos:
	@echo "===== cluster-info ====="
	@kubectl $(KUBEOPT) cluster-info
	@echo "===== get nodes  ====="
	@kubectl $(KUBEOPT) get nodes
	@echo "===== get componentstatus ====="
	@kubectl $(KUBEOPT) get componentstatus
	@echo "===== get all -n kube-system ====="
	@kubectl $(KUBEOPT) get all -n kube-system
	@kubectl $(KUBEOPT) get pods --all-namespaces

proxy:
	kubectl $(KUBEOPT) proxy &

k8s-%:
	ssh -F $(INV)/ssh-config $@

dash: dashboard-createuser dashboard-token proxy dashboard-open

# See https://github.com/kubernetes-sigs/kubespray/blob/master/docs/vagrant.md
dashboard-token:
	kubectl $(KUBEOPT) -n kube-system describe secret $(shell kubectl $(KUBEOPT) -n kube-system get secret | grep admin-user | awk '{print $$1}')
	#kubectl $(KUBEOPT) -n kube-system describe secret kubernetes-dashboard-token | grep 'token:' | grep -o '[^ ]\+$$'

dashboard-createuser:
	kubectl $(KUBEOPT) apply -f user/svc-account 
	kubectl $(KUBEOPT) apply -f user/role-binding
	#kubectl $(KUBEOPT) apply -f contrib/misc/clusteradmin-rbac.yml

dashboard-open:
	xdg-open http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/\#!/login


kubeadmin:
	[ -d $@ ] || mkdir $@

mito:
	[ -z '$(PROXY)' ] || export https_proxy=$(PROXY) ; [ -z $(PROXY) ] || export http_proxy=$(PROXY) ; ansible-playbook -c mycluster mitogen.yml -vv

# External tools k9s and popeye
runk9s: k9s
	./k9s -A --kubeconfig inventory/mycluster/kubeconfig

runpop: popeye
	./popeye -A --kubeconfig inventory/mycluster/kubeconfig

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

ssh%:
	vagrant ssh-config > /tmp/ssh-config
	ssh -F /tmp/ssh-config k8s-$*

