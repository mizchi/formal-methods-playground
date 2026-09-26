"""terraform show -json の出力から、IAM ロールの AssumeRole の関係を Alloy の事実として書き出す。

usage: python3 extract.py plan.json > iam_facts.als
"""
import fnmatch
import json
import sys

ADMIN_POLICIES = {"arn:aws:iam::aws:policy/AdministratorAccess"}


def as_list(x):
    return x if isinstance(x, list) else [x]


def allows(statement, action):
    return statement.get("Effect") == "Allow" and any(
        fnmatch.fnmatch(action, a) for a in as_list(statement.get("Action", []))
    )


plan = json.load(open(sys.argv[1]))
resources = plan["planned_values"]["root_module"]["resources"]
account = None
roles = {}  # name -> {"arn", "trust": [...], "resources": [...], "admin": bool}

for r in resources:
    v = r["values"]
    if r["type"] == "aws_iam_role":
        trust = []
        for s in json.loads(v["assume_role_policy"])["Statement"]:
            if allows(s, "sts:AssumeRole"):
                trust += as_list(s.get("Principal", {}).get("AWS", []))
        roles.setdefault(v["name"], {"resources": [], "admin": False})["trust"] = trust

for r in resources:
    v = r["values"]
    if r["type"] == "aws_iam_role_policy":
        for s in json.loads(v["policy"])["Statement"]:
            if allows(s, "sts:AssumeRole"):
                roles[v["role"]]["resources"] += as_list(s.get("Resource", []))
            if allows(s, "*") and "*" in as_list(s.get("Resource", [])):
                roles[v["role"]]["admin"] = True
    if r["type"] == "aws_iam_role_policy_attachment" and v["policy_arn"] in ADMIN_POLICIES:
        roles[v["role"]]["admin"] = True

# ロールの ARN は、信頼ポリシーに出てくるアカウント ID から組み立てる
for role in roles.values():
    for p in role["trust"]:
        if p.startswith("arn:aws:iam::"):
            account = p.split(":")[4]
for name, role in roles.items():
    role["arn"] = f"arn:aws:iam::{account}:role/{name}"
root = f"arn:aws:iam::{account}:root"


def can_assume(a, b):
    """a のポリシーが b を許し、b の信頼ポリシーが a (またはアカウントの root) を許す"""
    permitted = any(fnmatch.fnmatch(roles[b]["arn"], pat) for pat in roles[a]["resources"])
    trusted = roles[a]["arn"] in roles[b]["trust"] or root in roles[b]["trust"]
    return permitted and trusted


edges = [(a, b) for a in roles for b in roles if a != b and can_assume(a, b)]
entry = [n for n, r in roles.items() if root in r["trust"]]
admin = [n for n, r in roles.items() if r["admin"]]
union = lambda xs: " + ".join(xs) if xs else "none"

print("-- extract.py が terraform show -json から生成した。手で編集しない")
print("module iam_facts\n")
print("abstract sig Role { canAssume: set Role }")
print(f"one sig {', '.join(sorted(roles))} extends Role {{}}\n")
print("-- 人がアカウントから直接引き受けられるロール")
print("sig Entry in Role {}")
print("-- 管理者権限を持つロール")
print("sig Privileged in Role {}\n")
print("fact Extracted {")
print(f"  canAssume = {union([f'{a}->{b}' for a, b in edges])}")
print(f"  Entry = {union(entry)}")
print(f"  Privileged = {union(admin)}")
print("}")
