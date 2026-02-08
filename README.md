# IND Protocol

IND (Inheritance Dollar) is a programmable inheritance protocol that allows a sender
to define time-locked transfers with revocation guarantees.

This repository contains the protocol specification and reference design.
The project is currently in **pre-alpha** stage.

## Core principles

- The sender defines when a transfer becomes effective (never less than 24 hours).
- During the waiting period, the sender may **reduce** the waiting time (never below 24 hours).
- The sender may revoke the transfer before the effective time using separate revocation keys.
- All time values are expressed in **seconds** at protocol level.
- Recipients (including smart contracts and markets) must respect the waiting period.

## Status

- Specification: in progress
- Smart contracts: not yet implemented
- Audits: not started
