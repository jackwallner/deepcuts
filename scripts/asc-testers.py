#!/usr/bin/env python3
"""Make sure the internal TestFlight group "Family" exists with every build and the family testers in it.

Internal groups skip Beta App Review; testers must already be App Store Connect users.
Non-admin testers are locked to Deep Cuts: any other app access they gain is removed on each run.
"""
from __future__ import annotations

import asc_lib

APP_ID = "6825448110"
GROUP = "Family"
TESTERS = {"wallners@gmail.com": ("John", "Wallner"), "jackwallner@gmail.com": ("Jack", "Wallner"),
           "emiwallner@gmail.com": ("Emi", "Wallner"), "michaelhonig@msn.com": ("Michael", "Honig"),
           "ccsincorp93@gmail.com": ("Scott", "Johnston")}


def main() -> None:
    c = asc_lib.ASCClient.from_credentials()
    # Locking rewrites a user's app access, which drops their tester membership, so lock before
    # reading the group and the loop below adds them back.
    all_users = c.get("/users?limit=200").get("data", [])
    users = {u["attributes"]["username"] for u in all_users}
    for u in all_users:
        lock_to_app(c, u)
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


def lock_to_app(c: asc_lib.ASCClient, user: dict) -> None:
    """Keep a non-admin tester's App Store Connect access to this app only."""
    a = user["attributes"]
    if a["username"] not in TESTERS or "ADMIN" in a["roles"]:
        return
    apps = {x["id"] for x in c.get(f"/users/{user['id']}/visibleApps?limit=200").get("data", [])}
    if not a["allAppsVisible"] and apps == {APP_ID}:
        return
    c.patch(f"/users/{user['id']}", {"data": {"type": "users", "id": user["id"],
                                               "attributes": {"allAppsVisible": False}}})
    c.patch(f"/users/{user['id']}/relationships/visibleApps",
            {"data": [{"type": "apps", "id": APP_ID}]})
    print(f"locked {a['username']} to this app (had {sorted(apps) or 'all apps'})")


if __name__ == "__main__":
    main()
