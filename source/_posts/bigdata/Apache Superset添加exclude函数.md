---
title: Apache Superset添加EXCLUDE函数
tags:
  - 'BI'
  - 'Apache Superset'
categories:
  - [BI]
top_img: 
date: 2023-01-11 11:45:16
updated: 2023-01-11 11:45:16
cover:
description:
keywords:
---

## 前言

> 因为业务需求，需要一个类似于Tableau中的exclude函数的功能。
>
> 例如：
>
> 若要查看一段时间内每个国家/地区的平均血压，但不按男性和女性进行划分，请使用 EXCLUDE 详细级别表达式 `{EXCLUDE [Sex] : AVG[Average blood pressure]}`。
>
> 这个函数的功能对于业务来说非常重要，但是Apache Superset中没有此类功能，因此需要修改Apache Superset源码，为其添加上这个功能！这是一个不小的挑战！



## 新功能实现计划

- 1、获取由用户拖拽生成的BI图表的SQL语句。
- 2、拦截SQL语句进行改写，例如`{EXCLUDE [Sex] : AVG[blood-pressure]}`:
  - 1、去除原SQL语句中的Sex维度信息和针对Sex的过滤条件，得到新的SQL
  - 2、基于新的SQL发出对于blood-pressure度量来说是正确的聚合SQL，得到正确结果集
  - 3、获取正确结果集中排除Sex维度后正确的blood-pressure度量聚合值。
  - 4、利用正确的结果集中正确的部分，对原SQL语句得到的结果集进行更新

- 3、将改写后的结果集发送回前端。

# Apache Superset源码定位

- Apache Superset后端以python的web框架Flask开发，代码结构清晰，代码质量优秀。
- 添加新功能的代码集中在源码中：superset/charts/data/api.py中。主要修改的方法为`def data(self) -> Response:`

## show code

```python
    @expose("/data", methods=["POST"])
    @protect()
    @statsd_metrics
    @event_logger.log_this_with_context(
        action=lambda self, *args, **kwargs: f"{self.__class__.__name__}.data",
        log_to_statsd=False,
    )
    def data(self) -> Response:
        """
        Takes a query context constructed in the client and returns payload
        data response for the given query.
        ---
        post:
          description: >-
            Takes a query context constructed in the client and returns payload data
            response for the given query.
          requestBody:
            description: >-
              A query context consists of a datasource from which to fetch data
              and one or many query objects.
            required: true
            content:
              application/json:
                schema:
                  $ref: "#/components/schemas/ChartDataQueryContextSchema"
          responses:
            200:
              description: Query result
              content:
                application/json:
                  schema:
                    $ref: "#/components/schemas/ChartDataResponseSchema"
            202:
              description: Async job details
              content:
                application/json:
                  schema:
                    $ref: "#/components/schemas/ChartDataAsyncResponseSchema"
            400:
              $ref: '#/components/responses/400'
            401:
              $ref: '#/components/responses/401'
            500:
              $ref: '#/components/responses/500'
        """
        json_body = None
        if request.is_json:
            json_body = request.json
        elif request.form.get("form_data"):
            # CSV export submits regular form data
            try:
                json_body = json.loads(request.form["form_data"])
            except (TypeError, json.JSONDecodeError):
                pass

        if json_body is None:
            return self.response_400(message=_("Request is not JSON"))

        logger.info("===231===")
        # logger.error("json_body......")
        # logger.error(json_body)

        try:
            query_context = self._create_query_context_from_form(json_body)
            command = ChartDataCommand(query_context)
            command.validate()
        except DatasourceNotFound as error:
            return self.response_404()
        except QueryObjectValidationError as error:
            return self.response_400(message=error.message)
        except ValidationError as error:
            return self.response_400(
                message=_(
                    "Request is incorrect: %(error)s", error=error.normalized_messages()
                )
            )

        # TODO: support CSV, SQL query and other non-JSON types
        if (
            is_feature_enabled("GLOBAL_ASYNC_QUERIES")
            and query_context.result_format == ChartDataResultFormat.JSON
            and query_context.result_type == ChartDataResultType.FULL
        ):
            return self._run_async(json_body, command)

        form_data = json_body.get("form_data")
        logger.warning("查询成功。。。form_data")
        logger.warning(form_data)

        try:
            result = command.run(force_cached=False)
            logger.info("result ... a")
            logger.info(result)
        except ChartDataCacheLoadError as exc:
            return self.response_422(message=exc.message)
        except ChartDataQueryFailedError as exc:
            return self.response_400(message=exc.message)


        ############################# execte without symp query

        json_body_without_symp = None

        has_symp = False
        # [{'col': 'shop_id', 'op': '==', 'val': '121'}]
        filters = json_body["queries"][0]["filters"]
        # logger.info(filters)
        for filter in filters:
            if filter["col"] == "shop_id":
                # 去除json_body中的过滤条件，构建json_body_2,进行查询，获取正确的input聚合数据
                filters.remove(filter)
                has_symp = True

        if has_symp :
            json_body["queries"][0]["filters"] = filters
            json_body_without_symp = json_body

        # logger.info("json_body_without_symp......")
        # logger.info(json_body_without_symp)

        try:
            query_context_without_symp = self._create_query_context_from_form(json_body_without_symp)
            command_without_symp = ChartDataCommand(query_context_without_symp)
            command_without_symp.validate()
        except DatasourceNotFound as error:
            return self.response_404()
        except QueryObjectValidationError as error:
            return self.response_400(message=error.message)
        except ValidationError as error:
            return self.response_400(
                message=_(
                    "Request is incorrect: %(error)s", error=error.normalized_messages()
                )
            )

        # TODO: support CSV, SQL query and other non-JSON types
        if (
            is_feature_enabled("GLOBAL_ASYNC_QUERIES")
            and query_context_without_symp.result_format == ChartDataResultFormat.JSON
            and query_context_without_symp.result_type == ChartDataResultType.FULL
        ):
            return self._run_async(json_body_without_symp, command_without_symp)

        #############################

        form_data_without_symp = json_body_without_symp.get("form_data")

        logger.info("查询成功。。。form_data_without_symp")
        logger.info(form_data_without_symp)


        try:
            result_without_symp = command_without_symp.run(force_cached=False)
            logger.info("result ... b")
            logger.info(result_without_symp)
        except ChartDataCacheLoadError as exc:
            return self.response_422(message=exc.message)
        except ChartDataQueryFailedError as exc:
            return self.response_400(message=exc.message)

        ## 重构result结果，返回前端

        return self._get_data_response(
            command, form_data=form_data, datasource=query_context.datasource
        )
```

