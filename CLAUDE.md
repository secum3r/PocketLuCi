# CLAUDE.md — iRouter

Project context for Claude. Updated as the project evolves.

---

## Project Overview

**PocketLuCi** is a native iOS app (SwiftUI, iOS 17+) for managing a home OPEN-WRT router.
It allows the user to restrict internet access to specific devices and groups (e.g. kids' iPads, TVs),
and to create, edit, and toggle DD-WRT access restriction schedules — all from their iPhone.

**Local project path:** `~/Downloads/DevWork/DDWRTManager`

It allows users to 
1. View the currently connected devices and their information e.g. IP Address, MAC Address, Hostname
2. Mange Firewall rules
3. Parental Control, this includes restricting access to internet, schedules, restricting access to certain sites for certain devices or group of devices. Example: User can create a group of all kids devices and apply these rules to, schedule restrictions etc. 
4. Restart the router. 
5. Settings page - would allow the user to define the Router IP, username and password for connections, please note, these routers may not have a certificate but given this would be internal we would like to allow the user access via app.
6. Light or Dark mode selection 





FEATURES:


  ┌───────────────────┬──────────────────────────────────────────────┐                                                                                                          
  │      Feature      │                 Description                  │
  ├───────────────────┼──────────────────────────────────────────────┤                                                                                                          
  │ Devices View      │ Connected devices with IP, MAC, hostname     │                                                                                                          
  ├───────────────────┼──────────────────────────────────────────────┤                                                                                                          
  │ Firewall Rules    │ Manage router firewall configs               │                                                                                                          
  ├───────────────────┼──────────────────────────────────────────────┤                                                                                                          
  │ Parental Controls │ Device groups, schedules, site blocking      │                                                                                                          
  ├───────────────────┼──────────────────────────────────────────────┤                                                                                                          
  │ Router Control    │ Restart router                               │
  ├───────────────────┼──────────────────────────────────────────────┤                                                                                                          
  │ Settings          │ Router IP, credentials (allow non-cert HTTP) │
  ├───────────────────┼──────────────────────────────────────────────┤                                                                                                          
  │ Themes            │ Light/dark mode                              │
  └───────────────────┴──────────────────────────────────────────────┘                                                                                                          
