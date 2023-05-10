---
title: Superset配置LDAP踩坑指南
tags:
  - 'Apache Superset'
categories:
  - [Superset]
top_img: 
date: 2023-05-11 11:45:16
updated: 2023-05-11 11:45:16
cover:
description:
keywords:
---

## 前言

由于公司LDAP奇怪的信息管理，导致superset按照官方文档配置LDAP的时候，遇到一系列问题，不是认证失败，就是认证信息不合理。因此开始漫长的阅读[Flask-AppBuilder](https://github.com/dpgaspar/Flask-AppBuilder/)源码，来正确的配置LDAP。



## 配置过程

- 1、在superset的配置文件中，开启Flask-AppBuilder的日志输出。

  ```python
  # Whether to bump the logging level to ERROR on the flask_appbuilder package
  # Set to False if/when debugging FAB related issues like
  # permission management
  SILENCE_FAB = False
  ```

- 2、正确的配置入下

  ```python
  AUTH_LDAP_SERVER = "ldap://sdsdsds:389"
  AUTH_LDAP_SEARCH = "DC=xx,DC=cc,DC=com"
  
  # see flask_appbuilder.security.manager.BaseSecurityManager.auth_user_ldap
  # see flask_appbuilder.security.manager.BaseSecurityManager.auth_ldap_append_domain
  AUTH_LDAP_APPEND_DOMAIN = "xx.xx.com"
  AUTH_LDAP_SEARCH_FILTER = "(objectClass=user)"
  AUTH_LDAP_UID_FIELD = "sAMAccountName"
  # 由于大量用户邮箱相同，superset向数据库插入用户信息报邮箱相同的错误，导致认证失败，换一个不重复的字段
  AUTH_LDAP_EMAIL_FIELD = "userPrincipalName"
  ```

- 3、进入docker，运行`superset init `,以解决Admin权限的用户也无法查看所有用户的bug。



## 源码分析

LDAP认证源码集中在`flask_appbuilder.security.manager.BaseSecurityManager.auth_user_ldap`方法内：https://github.com/dpgaspar/Flask-AppBuilder/blob/master/flask_appbuilder/security/manager.py

- 1、查看源码发现，发现配置`AUTH_LDAP_APPEND_DOMAIN`这个字段可以直接通过网域账号通过认证，这样才满足我们的需求。而官方文档配置`AUTH_LDAP_BIND_USER/AUTH_LDAP_BIND_PASSWORD`这两个字段的方式，根本不满足我们的需求。

  ```python
      def auth_user_ldap(self, username, password):
          """
          Method for authenticating user with LDAP.
  
          NOTE: this depends on python-ldap module
  
          :param username: the username
          :param password: the password
          """
          # If no username is provided, go away
          if (username is None) or username == "":
              return None
  
          # Search the DB for this user
          user = self.find_user(username=username)
  
          # If user is not active, go away
          if user and (not user.is_active):
              return None
  
          # If user is not registered, and not self-registration, go away
          if (not user) and (not self.auth_user_registration):
              return None
  
          # Ensure python-ldap is installed
          try:
              import ldap
          except ImportError:
              log.error("python-ldap library is not installed")
              return None
  
          try:
              # LDAP certificate settings
              if self.auth_ldap_tls_cacertdir:
                  ldap.set_option(ldap.OPT_X_TLS_CACERTDIR, self.auth_ldap_tls_cacertdir)
              if self.auth_ldap_tls_cacertfile:
                  ldap.set_option(
                      ldap.OPT_X_TLS_CACERTFILE, self.auth_ldap_tls_cacertfile
                  )
              if self.auth_ldap_tls_certfile:
                  ldap.set_option(ldap.OPT_X_TLS_CERTFILE, self.auth_ldap_tls_certfile)
              if self.auth_ldap_tls_keyfile:
                  ldap.set_option(ldap.OPT_X_TLS_KEYFILE, self.auth_ldap_tls_keyfile)
              if self.auth_ldap_allow_self_signed:
                  ldap.set_option(ldap.OPT_X_TLS_REQUIRE_CERT, ldap.OPT_X_TLS_ALLOW)
                  ldap.set_option(ldap.OPT_X_TLS_NEWCTX, 0)
              elif self.auth_ldap_tls_demand:
                  ldap.set_option(ldap.OPT_X_TLS_REQUIRE_CERT, ldap.OPT_X_TLS_DEMAND)
                  ldap.set_option(ldap.OPT_X_TLS_NEWCTX, 0)
  
              # Initialise LDAP connection
              con = ldap.initialize(self.auth_ldap_server)
              con.set_option(ldap.OPT_REFERRALS, 0)
              if self.auth_ldap_use_tls:
                  try:
                      con.start_tls_s()
                  except Exception:
                      log.error(
                          LOGMSG_ERR_SEC_AUTH_LDAP_TLS.format(self.auth_ldap_server)
                      )
                      return None
  
              # Define variables, so we can check if they are set in later steps
              user_dn = None
              user_attributes = {}
  
              # Flow 1 - (Indirect Search Bind):
              #  - in this flow, special bind credentials are used to preform the
              #    LDAP search
              #  - in this flow, AUTH_LDAP_SEARCH must be set
              if self.auth_ldap_bind_user:
                  # Bind with AUTH_LDAP_BIND_USER/AUTH_LDAP_BIND_PASSWORD
                  # (authorizes for LDAP search)
                  self._ldap_bind_indirect(ldap, con)
  
                  # Search for `username`
                  #  - returns the `user_dn` needed for binding to validate credentials
                  #  - returns the `user_attributes` needed for
                  #    AUTH_USER_REGISTRATION/AUTH_ROLES_SYNC_AT_LOGIN
                  if self.auth_ldap_search:
                      user_dn, user_attributes = self._search_ldap(ldap, con, username)
                  else:
                      log.error(
                          "AUTH_LDAP_SEARCH must be set when using AUTH_LDAP_BIND_USER"
                      )
                      return None
  
                  # If search failed, go away
                  if user_dn is None:
                      log.info(LOGMSG_WAR_SEC_NOLDAP_OBJ.format(username))
                      return None
  
                  # Bind with user_dn/password (validates credentials)
                  if not self._ldap_bind(ldap, con, user_dn, password):
                      if user:
                          self.update_user_auth_stat(user, False)
  
                      # Invalid credentials, go away
                      log.info(LOGMSG_WAR_SEC_LOGIN_FAILED.format(username))
                      return None
  
              # Flow 2 - (Direct Search Bind):
              #  - in this flow, the credentials provided by the end-user are used
              #    to preform the LDAP search
              #  - in this flow, we only search LDAP if AUTH_LDAP_SEARCH is set
              #     - features like AUTH_USER_REGISTRATION & AUTH_ROLES_SYNC_AT_LOGIN
              #       will only work if AUTH_LDAP_SEARCH is set
              else:
                  # Copy the provided username (so we can apply formatters)
                  bind_username = username
  
                  # update `bind_username` by applying AUTH_LDAP_APPEND_DOMAIN
                  #  - for Microsoft AD, which allows binding with userPrincipalName
                  if self.auth_ldap_append_domain:
                      bind_username = bind_username + "@" + self.auth_ldap_append_domain
  
                  # Update `bind_username` by applying AUTH_LDAP_USERNAME_FORMAT
                  #  - for transforming the username into a DN,
                  #    for example: "uid=%s,ou=example,o=test"
                  if self.auth_ldap_username_format:
                      bind_username = self.auth_ldap_username_format % bind_username
  
                  # Bind with bind_username/password
                  # (validates credentials & authorizes for LDAP search)
                  if not self._ldap_bind(ldap, con, bind_username, password):
                      if user:
                          self.update_user_auth_stat(user, False)
  
                      # Invalid credentials, go away
                      log.info(LOGMSG_WAR_SEC_LOGIN_FAILED.format(bind_username))
                      return None
  
                  # Search for `username` (if AUTH_LDAP_SEARCH is set)
                  #  - returns the `user_attributes`
                  #    needed for AUTH_USER_REGISTRATION/AUTH_ROLES_SYNC_AT_LOGIN
                  #  - we search on `username` not `bind_username`,
                  #    because AUTH_LDAP_APPEND_DOMAIN and AUTH_LDAP_USERNAME_FORMAT
                  #    would result in an invalid search filter
                  if self.auth_ldap_search:
                      user_dn, user_attributes = self._search_ldap(ldap, con, username)
  
                      # If search failed, go away
                      if user_dn is None:
                          log.info(LOGMSG_WAR_SEC_NOLDAP_OBJ.format(username))
                          return None
  
              # Sync the user's roles
              if user and user_attributes and self.auth_roles_sync_at_login:
                  user.roles = self._ldap_calculate_user_roles(user_attributes)
                  log.debug(
                      "Calculated new roles for user='{0}' as: {1}".format(
                          user_dn, user.roles
                      )
                  )
  
              # If the user is new, register them
              if (not user) and user_attributes and self.auth_user_registration:
                  user = self.add_user(
                      username=username,
                      first_name=self.ldap_extract(
                          user_attributes, self.auth_ldap_firstname_field, ""
                      ),
                      last_name=self.ldap_extract(
                          user_attributes, self.auth_ldap_lastname_field, ""
                      ),
                      email=self.ldap_extract(
                          user_attributes,
                          self.auth_ldap_email_field,
                          f"{username}@email.notfound",
                      ),
                      role=self._ldap_calculate_user_roles(user_attributes),
                  )
                  log.debug("New user registered: {0}".format(user))
  
                  # If user registration failed, go away
                  if not user:
                      log.info(LOGMSG_ERR_SEC_ADD_REGISTER_USER.format(username))
                      return None
  
              # LOGIN SUCCESS (only if user is now registered)
              if user:
                  self.update_user_auth_stat(user)
                  return user
              else:
                  return None
  
          except ldap.LDAPError as e:
              msg = None
              if isinstance(e, dict):
                  msg = getattr(e, "message", None)
              if (msg is not None) and ("desc" in msg):
                  log.error(LOGMSG_ERR_SEC_AUTH_LDAP.format(e.message["desc"]))
                  return None
              else:
                  log.error(e)
                  return None
  ```

- 2、通过阅读下面的源码，这样配置`AUTH_LDAP_SEARCH_FILTER = "(objectClass=user)"`,才满足我们的需求，想用那个字段登陆，就用那个字段登录。

  ```python
      def _search_ldap(self, ldap, con, username):
          """
          Searches LDAP for user.
  
          :param ldap: The ldap module reference
          :param con: The ldap connection
          :param username: username to match with AUTH_LDAP_UID_FIELD
          :return: ldap object array
          """
          # always check AUTH_LDAP_SEARCH is set before calling this method
          assert self.auth_ldap_search, "AUTH_LDAP_SEARCH must be set"
  
          # build the filter string for the LDAP search
          # LDAP search的核心逻辑
          if self.auth_ldap_search_filter:
              filter_str = "(&{0}({1}={2}))".format(
                  self.auth_ldap_search_filter, self.auth_ldap_uid_field, username
              )
          else:
              filter_str = "({0}={1})".format(self.auth_ldap_uid_field, username)
  
          # build what fields to request in the LDAP search
          request_fields = [
              self.auth_ldap_firstname_field,
              self.auth_ldap_lastname_field,
              self.auth_ldap_email_field,
          ]
          if len(self.auth_roles_mapping) > 0:
              request_fields.append(self.auth_ldap_group_field)
  
          # preform the LDAP search
          log.debug(
              "LDAP search for '{0}' with fields {1} in scope '{2}'".format(
                  filter_str, request_fields, self.auth_ldap_search
              )
          )
          raw_search_result = con.search_s(
              self.auth_ldap_search, ldap.SCOPE_SUBTREE, filter_str, request_fields
          )
          log.debug("LDAP search returned: {0}".format(raw_search_result))
  
          # Remove any search referrals from results
          search_result = [
              (dn, attrs)
              for dn, attrs in raw_search_result
              if dn is not None and isinstance(attrs, dict)
          ]
  
          # only continue if 0 or 1 results were returned
          if len(search_result) > 1:
              log.error(
                  "LDAP search for '{0}' in scope '{1}' returned multiple results".format(
                      filter_str, self.auth_ldap_search
                  )
              )
              return None, None
  
          try:
              # extract the DN
              user_dn = search_result[0][0]
              # extract the other attributes
              user_info = search_result[0][1]
              # return
              return user_dn, user_info
          except (IndexError, NameError):
              return None, None
  ```

  
