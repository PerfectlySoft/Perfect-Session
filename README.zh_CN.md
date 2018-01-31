# Perfect Sessions (core library)

<p align="center">
    <a href="http://perfect.org/get-involved.html" target="_blank">
        <img src="http://perfect.org/assets/github/perfect_github_2_0_0.jpg" alt="Get Involed with Perfect!" width="854" />
    </a>
</p>

<p align="center">
    <a href="https://github.com/PerfectlySoft/Perfect" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_1_Star.jpg" alt="Star Perfect On Github" />
    </a>  
    <a href="http://stackoverflow.com/questions/tagged/perfect" target="_blank">
        <img src="http://www.perfect.org/github/perfect_gh_button_2_SO.jpg" alt="Stack Overflow" />
    </a>  
    <a href="https://twitter.com/perfectlysoft" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_3_twit.jpg" alt="Follow Perfect on Twitter" />
    </a>  
    <a href="http://perfect.ly" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_4_slack.jpg" alt="Join the Perfect Slack" />
    </a>
</p>

<p align="center">
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Swift-4.0-orange.svg?style=flat" alt="Swift 4.0">
    </a>
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Platforms-OS%20X%20%7C%20Linux%20-lightgray.svg?style=flat" alt="Platforms OS X | Linux">
    </a>
    <a href="http://perfect.org/licensing.html" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache-lightgrey.svg?style=flat" alt="License Apache">
    </a>
    <a href="http://twitter.com/PerfectlySoft" target="_blank">
        <img src="https://img.shields.io/badge/Twitter-@PerfectlySoft-blue.svg?style=flat" alt="PerfectlySoft Twitter">
    </a>
    <a href="http://perfect.ly" target="_blank">
        <img src="http://perfect.ly/badge.svg" alt="Slack Status">
    </a>
</p>

Perfect Session 核心对象库，包括内存驱动

演示程序可以在以下链接找到： [https://github.com/PerfectExamples/Perfect-Session-Memory-Demo](https://github.com/PerfectExamples/Perfect-Session-Memory-Demo) 用于展示如何通过内存驱动使用Session

## Swift 兼容性

目前本函数库与 **Xcode 9.2** 及 **Swift 4.0.3** 工具链兼容

## 编译

请向Package.swift追加依存关系：

``` swift
.Package(url:"https://github.com/PerfectlySoft/Perfect-Session.git", majorVersion: 3)
```

## 数据库驱动

建议使用数据库作为保存会话过程的驱动，目前有效驱动包括：

* [PostgreSQL](https://github.com/PerfectlySoft/Perfect-Session-PostgreSQL)
* [MySQL](https://github.com/PerfectlySoft/Perfect-Session-MySQL)
* [CouchDB](https://github.com/PerfectlySoft/Perfect-Session-CouchDB)
* [MongoDB](https://github.com/PerfectlySoft/Perfect-Session-MongoDB)
* [Redis](https://github.com/PerfectlySoft/Perfect-Session-Redis)
* [SQLite](https://github.com/PerfectlySoft/Perfect-Session-SQLite)

如果您需要使用上述任何一个驱动，请不要再引用本模块作为依存关系，直接应用即可。

## 问题报告、内容贡献和客户支持

我们目前正在过渡到使用JIRA来处理所有源代码资源合并申请、修复漏洞以及其它有关问题。因此，GitHub 的“issues”问题报告功能已经被禁用了。

如果您发现了问题，或者希望为改进本文提供意见和建议，[请在这里指出](http://jira.perfect.org:8080/servicedesk/customer/portal/1).

在您开始之前，请参阅[目前待解决的问题清单](http://jira.perfect.org:8080/projects/ISS/issues).


## 更多信息
关于本项目更多内容，请参考[perfect.org](http://perfect.org).
