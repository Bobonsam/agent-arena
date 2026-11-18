#!/usr/bin/env python3
"""Local logic tests for AgentArena using eth-tester (py-evm).
Covers: Agent ID gate, check-in points/streak, mission predict/resolve/claim,
owner limits, pause. Run: ./venv/bin/python test_local.py"""
import json, sys
from web3 import Web3
from eth_tester import EthereumTester
from web3.providers.eth_tester import EthereumTesterProvider

t = EthereumTester()
w3 = Web3(EthereumTesterProvider(t))
owner, alice, bob, carol = w3.eth.accounts[:4]

def load(name):
    with open(f"build/{name}.json") as f:
        j = json.load(f)
    return j["abi"], j["bytecode"]

def deploy(name, *args, sender):
    abi, bc = load(name)
    c = w3.eth.contract(abi=abi, bytecode=bc)
    txh = c.constructor(*args).transact({"from": sender})
    rcpt = w3.eth.get_transaction_receipt(txh)
    assert rcpt.status == 1, f"deploy {name} failed"
    return w3.eth.contract(address=rcpt.contractAddress, abi=abi), rcpt

def ok(fn, desc):
    rcpt = w3.eth.get_transaction_receipt(fn())
    assert rcpt.status == 1, f"FAILED (tx status 0): {desc}"
    print(f"  PASS tx: {desc} (gas {rcpt.gasUsed})")
    return rcpt

def reverts(fn, desc, needle=None):
    try:
        fn()
    except Exception as e:
        if needle and needle not in str(e):
            print(f"  PASS revert (other reason): {desc} -> {str(e)[:90]}")
        else:
            print(f"  PASS revert: {desc}")
        return
    raise AssertionError(f"expected revert but succeeded: {desc}")

DAY = 86400
now = w3.eth.get_block("latest").timestamp
today = now // DAY

mock, _ = deploy("MockAgentID", sender=owner)
arena, arcpt = deploy("AgentArena", mock.address, owner, sender=owner)
print(f"deployed: mock={mock.address} arena={arena.address} deploy_gas={arcpt.gasUsed}")

# Agent IDs: alice + carol hold one, bob holds none
mock.functions.mint(alice).transact({"from": owner})
mock.functions.mint(carol).transact({"from": owner})

print("== gate ==")
reverts(lambda: arena.functions.checkIn().transact({"from": bob}), "bob (no Agent ID) checkIn blocked", "Agent ID required")

print("== check-in day 1 ==")
ok(lambda: arena.functions.checkIn().transact({"from": alice}), "alice checkIn")
p = arena.functions.getPlayer(alice).call()
assert (p[1], p[3]) == (1, 10), p  # streak 1, points 10
print(f"  PASS state: streak={p[1]} points={p[3]}")
reverts(lambda: arena.functions.checkIn().transact({"from": alice}), "alice double check-in same day blocked")

print("== mission for tomorrow, set by owner only ==")
reverts(lambda: arena.functions.setMission(today + 1, "BTC up tomorrow?", "Up;Down", 2).transact({"from": alice}), "non-owner setMission blocked")
ok(lambda: arena.functions.setMission(today + 1, "BTC up tomorrow?", "Up;Down", 2).transact({"from": owner}), "owner setMission(tomorrow)")
reverts(lambda: arena.functions.setMission(today + 1, "dup", "A;B", 2).transact({"from": owner}), "overwrite mission blocked")
reverts(lambda: arena.functions.predict(1).transact({"from": alice}), "predict before mission day blocked")

print("== travel to tomorrow ==")
t.time_travel((today + 1) * DAY + 3600)
assert arena.functions.today().call() == today + 1
ok(lambda: arena.functions.checkIn().transact({"from": alice}), "alice checkIn day 2")
p = arena.functions.getPlayer(alice).call()
assert (p[1], p[3]) == (2, 21), p  # streak 2 -> 10 + (10+1) = 21
print(f"  PASS state: streak={p[1]} points={p[3]} (streak bonus +1)")
ok(lambda: arena.functions.predict(1).transact({"from": alice}), "alice predict Up")
ok(lambda: arena.functions.predict(2).transact({"from": carol}), "carol predict Down")
reverts(lambda: arena.functions.predict(2).transact({"from": alice}), "alice second prediction blocked")
reverts(lambda: arena.functions.claimPrediction(today + 1).transact({"from": alice}), "claim before resolve blocked")
reverts(lambda: arena.functions.resolveMission(today + 1, 1).transact({"from": alice}), "non-owner resolve blocked")

print("== resolve + claim ==")
ok(lambda: arena.functions.resolveMission(today + 1, 1).transact({"from": owner}), "owner resolve (Up wins)")
reverts(lambda: arena.functions.resolveMission(today + 1, 2).transact({"from": owner}), "re-resolve blocked")
ok(lambda: arena.functions.claimPrediction(today + 1).transact({"from": alice}), "alice claim +50")
p = arena.functions.getPlayer(alice).call()
assert p[3] == 71, p  # 21 + 50
print(f"  PASS state: alice points={p[3]}")
reverts(lambda: arena.functions.claimPrediction(today + 1).transact({"from": alice}), "double claim blocked")
reverts(lambda: arena.functions.claimPrediction(today + 1).transact({"from": carol}), "wrong prediction claim blocked")

print("== streak reset after a skipped day ==")
t.time_travel((today + 3) * DAY + 3600)  # skip day today+2 entirely
ok(lambda: arena.functions.checkIn().transact({"from": alice}), "alice checkIn after gap")
p = arena.functions.getPlayer(alice).call()
assert (p[1], p[2]) == (1, 2), p  # streak reset to 1, best streak stays 2
print(f"  PASS state: streak={p[1]} bestStreak={p[2]}")

print("== pause ==")
ok(lambda: arena.functions.setPaused(True).transact({"from": owner}), "owner pause")
reverts(lambda: arena.functions.checkIn().transact({"from": carol}), "checkIn while paused blocked")
ok(lambda: arena.functions.setPaused(False).transact({"from": owner}), "owner unpause")
ok(lambda: arena.functions.checkIn().transact({"from": carol}), "carol checkIn after unpause")

print("== leaderboard views ==")
assert arena.functions.playerCount().call() == 2
page = arena.functions.playersPage(0, 10).call()
assert set(page) == {alice, carol}, page
print(f"  PASS: playerCount=2, page ok")

print("\nALL LOCAL TESTS PASSED")
