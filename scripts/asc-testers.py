#!/usr/bin/env python3
"""Make sure the internal TestFlight group "Family" exists with every build and the family testers in it.

Internal groups skip Beta App Review; testers must already be App Store Connect users.
"""
from __future__ import annotations

import asc_lib

APP_ID = "6825448110"
GROUP = "Family"
TESTERS = {"wallners@gmail.com": ("John", "Wallner"), "jackwallner@gmail.com": ("Jack", "Wallner"),
           "emiwallner@gmail.com": ("Emi", "Wallner"), "michaelhonig@msn.com": ("Michael", "Honig")}


def main() -> None:
    c = asc_lib.ASCClient.from_credentials()
    groups = c.get(f"/apps/{APP_ID}/betaGroups").get("data", [])
    group = next((g for g in groups if g["attributes"]["name"] == GROUP), None)
    if not group:
        group = c.post("/betaGroups", {"data": {
            "type": "betaGroups",
            "attributes": {"name": GROUP, "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})["data"]
        print(f"created group {GROUP} {group['id']}")
    testers = c.get(f"/betaGroups/{group['id']}/betaTesters?limit=200").get("data", [])
    members = {t["attributes"]["email"] for t in testers}
    # Adding a tester to a group doesn't email them; an invitation does.
    for t in testers:
        if t["attributes"].get("state") == "NOT_INVITED":
            c.post("/betaTesterInvitations", {"data": {"type": "betaTesterInvitations", "relationships": {
                "app": {"data": {"type": "apps", "id": APP_ID}},
                "betaTester": {"data": {"type": "betaTesters", "id": t["id"]}}}}})
            print(f"invited {t['attributes']['email']}")
    users = {u["attributes"]["username"] for u in c.get("/users?limit=200").get("data", [])}
    for email, (first, last) in TESTERS.items():
        if email in members:
            print(f"in group: {email}")
            continue
        if email not in users:
            print(f"skip {email}: not an App Store Connect user")
            continue
        c.post("/betaTesters", {"data": {
            "type": "betaTesters",
            "attributes": {"email": email, "firstName": first, "lastName": last},
            "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}}}})
        print(f"added {email}")


if __name__ == "__main__":
    main()
