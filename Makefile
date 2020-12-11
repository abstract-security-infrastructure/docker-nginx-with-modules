nginx_version ?= mainline
cached_layers ?= true
flavor = tsuru

all:
	flavors=$$(jq -er '.flavors[].name' flavors.json) && \
	for f in $$flavors; do make flavor=$$f image; done

image:
	modules=$$(jq -er '.flavors[] | select(.name == "$(flavor)") | .modules | join(",")' flavors.json) && \
	lua_modules=$$(jq -er '.flavors[] | select(.name == "$(flavor)") | [ .lua_modules[]? ] | join(",")' flavors.json) && \
	docker build -t abstractsecurityinfrastructure/nginx-pre-labels-$(flavor):$(nginx_version) $$(if [ "$(cached_layers)" = "false" ]; then echo "--no-cache"; fi) --build-arg nginx_version=$(nginx_version) --build-arg modules="$$modules" --build-arg lua_modules="$$lua_modules" .
	module_names=$$(docker run --rm abstractsecurityinfrastructure/nginx-pre-labels-$(flavor):$(nginx_version) sh -c 'ls /etc/nginx/modules/*.so | grep -v debug | xargs -I{} basename {} .so | paste -sd "," -') && \
	echo "FROM abstractsecurityinfrastructure/nginx-pre-labels-$(flavor):$(nginx_version)" | docker build -t abstractsecurityinfrastructure/nginx-$(flavor):$(nginx_version) --label "io.abstractsecurityinfrastructure.nginx-modules=$$module_names" -

test:
	@docker rm -f test-abstractsecurityinfrastructure-nginx-$(flavor)-$(nginx_version) || true
	@docker create -p 8888:8080 --name test-abstractsecurityinfrastructure-nginx-$(flavor)-$(nginx_version) abstractsecurityinfrastructure/nginx-pre-labels-$(flavor):$(nginx_version) bash -c " \
	openssl req -x509 -newkey rsa:4096 -nodes -subj '/CN=localhost' -keyout /etc/nginx/key.pem -out /etc/nginx/cert.pem -days 365; \
	nginx -c /etc/nginx/nginx-$(flavor).conf"
	@docker cp $$PWD/test/nginx-$(flavor).conf test-abstractsecurityinfrastructure-nginx-$(flavor)-$(nginx_version):/etc/nginx/
	@MS_RULES_DIR=$$(mktemp -d); curl https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended -o $$MS_RULES_DIR/modsecurity_rules.conf; \
	curl https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/unicode.mapping -o $$MS_RULES_DIR/unicode.mapping; \
	docker cp $$MS_RULES_DIR/modsecurity_rules.conf test-abstractsecurityinfrastructure-nginx-$(flavor)-$(nginx_version):/etc/nginx; \
	docker cp $$MS_RULES_DIR/unicode.mapping test-abstractsecurityinfrastructure-nginx-$(flavor)-$(nginx_version):/etc/nginx; \
	rm -r $$MS_RULES_DIR || rm -r $$MS_RULES_DIR
	@docker start test-abstractsecurityinfrastructure-nginx-$(flavor)-$(nginx_version) && sleep 3
	@if [ "$$(curl http://localhost:8888)" != "nginx config check ok" ]; then \
		$$(docker logs test-abstractsecurityinfrastructure-nginx-$(flavor)-$(nginx_version)); \
		@docker rm -f test-abstractsecurityinfrastructure-nginx-$(flavor)-$(nginx_version) || true \
		exit 1; \
	fi
	@docker rm -f test-abstractsecurityinfrastructure-nginx-$(flavor)-$(nginx_version) || true; \

.PHONY: all flavor test
