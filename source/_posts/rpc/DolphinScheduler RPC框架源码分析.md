---
title: DolphinScheduler RPC框架源码分析
tags:
  - 'dolphinscheduler'
categories:
  - [RPC]
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
date: 2023-07-09 21:07:13
updated: 2022-07-09 21:07:13
cover:
description:
keywords:
---

## 前言

截至2023-07-09，DolphinScheduler3.x最新版本Dev分支，DolphinScheduler中虽然基于Netty实现了一个简单的RPC框架，但是并没有使用，或者说使用的不是完整版的RPC框架。其中大量直接使用Netty Client发送网络请求，并没有使用动态代理简化或屏蔽掉通信细节，虽然在`org.apache.dolphinscheduler.rpc`包中已经有了完整实现。

本文主要分析`org.apache.dolphinscheduler.rpc`包中完整的RPC实现，虽然在DolphinScheduler中没有被使用。但是很多代码是共用的。



## 源码分析

### Rpc通信协议Protocol

定义在org.apache.dolphinscheduler.rpc.protocol.MessageHeader类中，没有什么好说的，差不多的套路。

- 一字节的version
- 一字节的eventType：HEARTBEAT、REQUEST、RESPONSE
- 四字节的msgLength
- ......
- 一字节的serialization类型：dolphinscheduler目前实现了一种基于ProtoStuff。

```java
public class MessageHeader {
	
    private byte version = 1;

    private byte eventType;

    private int msgLength = 0;

    private long requestId = 0L;

    private byte serialization = 0;

    private short magic = RpcProtocolConstants.MAGIC;
}
```



### 基于Netty进行网络通信

编解码，心跳机制属于模板代码，不做介绍。核心业务逻辑集中在Netty的Handler中：`org.apache.dolphinscheduler.rpc.remote.NettyClientHandler`和`org.apache.dolphinscheduler.rpc.remote.NettyServerHandler`。

```java
    /**
     * RPC Client实际进行RPC方法调用的地方：
     * 1、借助Netty进行网络传输、编解码
     * 2、channel.writeAndFlush(protocol)：
     *      1、RpcProtocol：先被NettyEncoder进行解码，RpcProtocol -> ByteBuf字节流
     *      2、然后NettyEncoder会将Encode后的字节流发送给server端
     * 3、RPC Server接受到Client发送过来的字节流：
     *      1、先被NettyDecoder进行解码：ByteBuf字节流 -> RpcProtocol对象
     *      2、NettyServerHandler#readHandler进行反射调用执行实际方法，然后将结果编码返回RPC Client
     * ##############
     * Netty Client端channel.writeAndFlush，会直接走Pipeline中的OutboundHandler
     * 而接受服务端返回的信息会走InboundHandler
     * @param host
     * @param protocol
     * @param async
     * @return
     */
    public RpcResponse sendMsg(Host host, RpcProtocol<RpcRequest> protocol, Boolean async) {

        // 从cache中获取netty channel
        Channel channel = getChannel(host);
        assert channel != null;

        RpcRequest request = protocol.getBody();
        RpcRequestCache rpcRequestCache = new RpcRequestCache();
        String serviceName = request.getClassName() + request.getMethodName();
        rpcRequestCache.setServiceName(serviceName);
        long reqId = protocol.getMsgHeader().getRequestId();
        RpcFuture future = null;
        if (Boolean.FALSE.equals(async)) {
            future = new RpcFuture(request, reqId);
            rpcRequestCache.setRpcFuture(future);
        }
        RpcRequestTable.put(protocol.getMsgHeader().getRequestId(), rpcRequestCache);
        channel.writeAndFlush(protocol);
        RpcResponse result = null;
        if (Boolean.TRUE.equals(async)) {
            result = new RpcResponse();
            result.setStatus((byte) 0);
            result.setResult(true);
            return result;
        }
        try {
            assert future != null;
            result = future.get();
        } catch (InterruptedException e) {
            log.error("send msg error，service name is {}", serviceName, e);
            Thread.currentThread().interrupt();
        }
        return result;
    }
```



### 动态代理

DolphinScheduler使用ByteBuddy框架进行客户端的动态代理，进行实际的网络请求，屏蔽相关细节。

```java
public class RpcClient implements IRpcClient {

    @Override
    public <T> T create(Class<T> clazz, Host host) throws Exception {
        return new ByteBuddy()
                // 指定父类
                .subclass(clazz)
                // 匹配由clazz声明的方法
                .method(isDeclaredBy(clazz))
                // 将匹配到的方法，交给ConsumerInterceptor进行代理增强：
                // 增加实际进行RPC调用的逻辑
                .intercept(MethodDelegation.to(new ConsumerInterceptor(host)))
                // 产生字节码
                .make()
                // 加载类
                .load(getClass().getClassLoader())
                .getLoaded()
                .getDeclaredConstructor().newInstance();
    }
}
```



```java
    /**
     * 动态代理只作用于RPC的Client端
     *
     * @param args @AllArguments: 将需要增强的方法的参数绑定于此
     * @param method @Origin Method: 被调用的原始方法
     * @return
     * @throws RemotingException
     */
    @RuntimeType
    public Object intercept(@AllArguments Object[] args, @Origin Method method) throws RemotingException {
        // 1、构造RpcRequest对象
        RpcRequest request = buildReq(args, method);

        // serviceName：类名+方法名。例如：IUserServicesay
        String serviceName = method.getDeclaringClass().getSimpleName() + method.getName();

        // ConsumerConfig: 存储每个被RPC调用方法的配置，比如：重试次数、异步与否
        ConsumerConfig consumerConfig = ConsumerConfigCache.getConfigByServersName(serviceName);
        if (null == consumerConfig) {
            consumerConfig = cacheServiceConfig(method, serviceName);
        }
        boolean async = consumerConfig.getAsync();

        int retries = consumerConfig.getRetries();

        // 构建RpcProtocol：RpcRequest + rpc协议相关信息
        RpcProtocol<RpcRequest> protocol = buildProtocol(request);

        while (retries-- > 0) {
            RpcResponse rsp;
            // 调用nettyClient进行网络请求
            rsp = nettyClient.sendMsg(host, protocol, async);
            // success
            if (null != rsp && rsp.getStatus() == 0) {
                return rsp.getResult();
            }
        }
        // execute fail
        throw new RemotingException("send msg error");

    }
```



### 服务发现

DolphinScheduler定义了两个注解`@RpcService("IUserService")`和`@Rpc(async = true, serviceCallback = UserCallback.class)`，简化Rpc的配置和服务的发现。

### Demo

```java
public class RpcTest {

    private NettyServer nettyServer;

    private IUserService userService;

    private Host host;

    @BeforeEach
    public void before() throws Exception {
        nettyServer = new NettyServer(new NettyServerConfig());
        IRpcClient rpcClient = new RpcClient();
        host = new Host("127.0.0.1", 12346);
        userService = rpcClient.create(IUserService.class, host);
    }

    @Test
    public void callTest(){
        Boolean hello = userService.say("hello");
        System.out.printf("Rpc Call Result %s\n", hello);

        System.out.println("###############");
        System.out.println(userService.callBackIsFalse("hello"));
    }

    @AfterEach
    public void after() {
        NettyClient.getInstance().close();
        nettyServer.close();
    }

}
```

