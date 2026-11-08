# Hosted Services / External Infra Disposition Tracker

**Date:** 2026-11-08  
**Status:** tracking only — **owner/decision not recorded in-repo** (operator/org decision required)  
**Context:** spectre-security retirement and OPA/ops absorption treated SonarQube/ZAP/hosted services/compose as “evaluate separately”; suite may own orchestration/evidence collection while services remain external dependencies.

## Items to disposition
| Item | Current assumption | Decision needed | Owner | Target date | Notes |
|---|---|---|---|---|---|
| SonarQube (hosted/service/compose) | External dependency (if used) | Retain, migrate, replace, or decommission; who operates; how evidence flows into suite | *(assign)* | *(set)* | Do not retire with archived repos until decided. |
| ZAP (hosted/service/compose) | External dependency (if used) | Retain/migrate/replace/decommission; ownership; suite orchestration integration | *(assign)* | *(set)* |  |
| Other hosted security services/compose from spectre-security era | Unknown in-repo | Inventory and disposition per service | *(assign)* | *(set)* | Confirm on host/org; record evidence. |

## Recording a decision
When decided, update this file with: decision, owner, evidence/links (no secrets), date, and any follow-up tasks (runbooks, suite actions, monitoring).
