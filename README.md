# Perfect Sessions (core library) [简体中文](README.zh_CN.md)

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

The Perfect Session core library, with Memory Driver.

Note that a demo is located at [https://github.com/PerfectExamples/Perfect-Session-Memory-Demo](https://github.com/PerfectExamples/Perfect-Session-Memory-Demo) that shows the operation of the in-memory driver included in the core library.

## Compatibility with Swift

The master branch of this project currently compiles with **Xcode 9.2** or the **Swift 4.0.3** toolchain on Ubuntu.

## Building

Add this project as a dependency in your Package.swift file.

``` swift
.Package(url:"https://github.com/PerfectlySoft/Perfect-Session.git", majorVersion: 3)
```

## Database-Specific Drivers

To use the Perfect Session driver with a database storage option (recommended) use one of the following database-specific modules:

* [PostgreSQL](https://github.com/PerfectlySoft/Perfect-Session-PostgreSQL)
* [MySQL](https://github.com/PerfectlySoft/Perfect-Session-MySQL)
* [CouchDB](https://github.com/PerfectlySoft/Perfect-Session-CouchDB)
* [MongoDB](https://github.com/PerfectlySoft/Perfect-Session-MongoDB)
* [Redis](https://github.com/PerfectlySoft/Perfect-Session-Redis)
* [SQLite](https://github.com/PerfectlySoft/Perfect-Session-SQLite)

If you use one of the database-specific modules, you do not need to include this module as a dependancy, as it is already included.

## Further Information
For more information on the Perfect project, please visit [perfect.org](http://perfect.org).
