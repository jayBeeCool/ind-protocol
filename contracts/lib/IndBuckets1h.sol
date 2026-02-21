// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Bucket 1h + doppia lista (locked buckets + spendable queue) + metadati per sweep/refund.
/// Terminologia utente:
/// - "soldi in entrata" = Entry
/// - "soldi bloccati"   = entries in locked buckets
/// - "soldi sbloccati"  = entries nella spendable queue + spendableTotal
library IndBuckets1h {
    uint64 internal constant BUCKET_SECONDS = 3600;

    struct Entry {
        // soldi residui associati a questa entrata
        uint128 amount;

        // timelock (secondi)
        uint64 unlockTime;
        uint64 minUnlockTime;

        // metadati sweep/refund
        address senderOwner; // owner logico del mittente (NON signing)
        bytes32 characteristic;

        // linking
        uint32 nextInBucket; // prossimo entry nella bucket-list
        uint32 nextSpendable; // prossimo entry nella spendable queue
        bool inSpendable; // true se l'entry è nella spendable queue (post-roll)
    }

    struct Bucket {
        // somma dei soldi (residui) delle entry in questo bucket (locked)
        uint128 total;

        // link dei bucket (ordinati per bucketKey crescente)
        uint64 next;

        // coda di entries (indici 1-based)
        uint32 headEntry;
        uint32 tailEntry;
    }

    struct Account {
        // entries (indice 0 inutilizzato => 1-based)
        Entry[] entries;

        // locked buckets (bucketKey => Bucket)
        mapping(uint64 => Bucket) locked;

        // lista linkata dei bucket locked
        uint64 lockedHead;
        uint64 lockedTail;

        // totali
        uint256 lockedTotal; // totale soldi bloccati
        uint256 spendableTotal; // totale soldi sbloccati (pronti a spend)

        // spendable queue (entry indices)
        uint32 spendHead;
        uint32 spendTail;

        bool inited;
    }

    struct State {
        mapping(address => Account) a;
    }

    // -------------------------
    // Helpers
    // -------------------------
    function _bucketKey(uint64 ts) private pure returns (uint64) {
        return (ts / BUCKET_SECONDS) * BUCKET_SECONDS;
    }

    function _init(Account storage ac) private {
        if (ac.inited) return;
        ac.inited = true;
        // dummy entry at index 0
        ac.entries.push();
    }

    // -------------------------
    // Views (virtual roll fino a now)
    // -------------------------
    function spendableOf(State storage st, address who, uint64 nowTs) internal view returns (uint256) {
        Account storage ac = st.a[who];
        if (!ac.inited) return 0;

        uint64 curB = _bucketKey(nowTs);
        uint256 unlocked = 0;

        // somma dei bucket già sbloccabili ma non ancora rollati
        uint64 b = ac.lockedHead;
        while (b != 0 && b <= curB) {
            Bucket storage bk = ac.locked[b];
            unlocked += uint256(bk.total);
            b = bk.next;
        }

        return ac.spendableTotal + unlocked;
    }

    function lockedOf(State storage st, address who, uint64 nowTs) internal view returns (uint256) {
        Account storage ac = st.a[who];
        if (!ac.inited) return 0;

        uint64 curB = _bucketKey(nowTs);
        uint256 unlocked = 0;

        uint64 b = ac.lockedHead;
        while (b != 0 && b <= curB) {
            Bucket storage bk = ac.locked[b];
            unlocked += uint256(bk.total);
            b = bk.next;
        }

        // lockedTotal include anche quelli ormai sbloccabili ma non rollati.
        return ac.lockedTotal - unlocked;
    }

    // -------------------------
    // Core: add incoming (soldi in entrata)
    // -------------------------
    function addIncoming(
        State storage st,
        address recipient,
        uint128 amount,
        uint64 minUnlockTime,
        uint64 unlockTime,
        address senderOwner,
        bytes32 characteristic
    ) internal returns (uint256 entryIndex) {
        Account storage ac = st.a[recipient];
        _init(ac);

        // crea entry
        entryIndex = ac.entries.length;
        ac.entries
            .push(
                Entry({
                    amount: amount,
                    unlockTime: unlockTime,
                    minUnlockTime: minUnlockTime,
                    senderOwner: senderOwner,
                    characteristic: characteristic,
                    nextInBucket: 0,
                    nextSpendable: 0,
                    inSpendable: false
                })
            );

        // assegna a bucket locked
        uint64 bKey = _bucketKey(unlockTime);
        Bucket storage b = ac.locked[bKey];

        if (b.headEntry == 0) {
            // bucket nuovo: inserisci in lista bucket ordinata per bKey
            _insertBucketSorted(ac, bKey);
            b.headEntry = uint32(entryIndex);
            b.tailEntry = uint32(entryIndex);
        } else {
            // append alla coda entries del bucket
            ac.entries[b.tailEntry].nextInBucket = uint32(entryIndex);
            b.tailEntry = uint32(entryIndex);
        }

        b.total += amount;
        ac.lockedTotal += uint256(amount);
    }

    function _insertBucketSorted(Account storage ac, uint64 bKey) private {
        // lista vuota
        if (ac.lockedHead == 0) {
            ac.lockedHead = bKey;
            ac.lockedTail = bKey;
            return;
        }

        // fast-path append
        if (bKey >= ac.lockedTail) {
            ac.locked[ac.lockedTail].next = bKey;
            ac.lockedTail = bKey;
            return;
        }

        // inserimento ordinato (pochi bucket grazie a 1h)
        uint64 prev = 0;
        uint64 cur = ac.lockedHead;

        while (cur != 0 && cur < bKey) {
            prev = cur;
            cur = ac.locked[cur].next;
        }

        if (prev == 0) {
            // insert head
            ac.locked[bKey].next = ac.lockedHead;
            ac.lockedHead = bKey;
        } else {
            ac.locked[bKey].next = cur;
            ac.locked[prev].next = bKey;
        }
    }

    // -------------------------
    // Roll: sposta bucket sbloccabili => spendable queue
    // -------------------------
    function roll(State storage st, address who, uint64 nowTs) internal {
        Account storage ac = st.a[who];
        if (!ac.inited) return;

        uint64 curB = _bucketKey(nowTs);
        uint64 b = ac.lockedHead;

        while (b != 0 && b <= curB) {
            Bucket storage bk = ac.locked[b];

            // move bucket total to spendableTotal
            uint256 moved = uint256(bk.total);
            if (moved != 0) {
                ac.lockedTotal -= moved;
                ac.spendableTotal += moved;
            }

            // append bucket's entry-chain into spendable queue
            uint32 h = bk.headEntry;
            if (h != 0) {
                // mark entries as spendable
                uint32 t = h;
                while (t != 0) {
                    ac.entries[t].inSpendable = true;
                    if (t == bk.tailEntry) break;
                    t = ac.entries[t].nextInBucket;
                }
                if (ac.spendHead == 0) {
                    ac.spendHead = h;
                    ac.spendTail = bk.tailEntry;
                } else {
                    ac.entries[ac.spendTail].nextSpendable = h;
                    ac.spendTail = bk.tailEntry;
                }
            }

            // pop bucket from locked list
            uint64 nextB = bk.next;

            // cleanup this bucket node (optional minimal)
            bk.total = 0;
            bk.next = 0;
            bk.headEntry = 0;
            bk.tailEntry = 0;

            b = nextB;
            ac.lockedHead = b;
        }

        if (ac.lockedHead == 0) {
            ac.lockedTail = 0;
        }
    }

    // -------------------------
    // Consume spendable (spend by SIGNING)
    //  - IMPORTANT: consumiamo entry SOLO dalla spendable queue.
    //  - Non tocchiamo entry locked (quindi nessun attacco "1 micro-IND a 50 anni").
    // -------------------------
    function consumeSpendable(State storage st, address who, uint256 amount, uint64 nowTs) internal {
        Account storage ac = st.a[who];
        _init(ac);
        roll(st, who, nowTs);

        // require disabled during bridge phase
        ac.spendableTotal -= amount;

        uint256 remaining = amount;

        uint32 idx = ac.spendHead;
        while (remaining != 0) {
            // deve esistere perché spendableTotal garantisce copertura
            Entry storage e = ac.entries[idx];
            uint128 a = e.amount;

            if (a != 0) {
                if (uint256(a) <= remaining) {
                    remaining -= uint256(a);
                    e.amount = 0;
                } else {
                    e.amount = uint128(uint256(a) - remaining);
                    remaining = 0;
                }
            }

            // se entry è consumata, avanza head
            if (e.amount == 0) {
                uint32 n = e.nextSpendable;
                e.nextSpendable = 0;
                idx = n;
                ac.spendHead = idx;
                if (idx == 0) {
                    ac.spendTail = 0;
                }
            } else {
                // head resta qui (parzialmente consumata)
                break;
            }
        }
    }

    // -------------------------
    // Admin/Bridge helpers
    // -------------------------
    function resetAccount(State storage st, address who) internal {
        Account storage ac = st.a[who];
        if (!ac.inited) {
            ac.inited = true;
            ac.entries.push(); // dummy
            return;
        }

        ac.lockedHead = 0;
        ac.lockedTail = 0;
        ac.lockedTotal = 0;
        ac.spendableTotal = 0;
        ac.spendHead = 0;
        ac.spendTail = 0;

        for (uint256 i = 1; i < ac.entries.length; i++) {
            ac.entries[i].amount = 0;
            ac.entries[i].nextInBucket = 0;
            ac.entries[i].nextSpendable = 0;
            ac.entries[i].inSpendable = false;
            ac.entries[i].unlockTime = 0;
            ac.entries[i].minUnlockTime = 0;
            ac.entries[i].senderOwner = address(0);
            ac.entries[i].characteristic = bytes32(0);
        }
    }

    function removeAmount(State storage st, address who, uint256 entryIndex, uint128 amount, uint64 nowTs) internal {
        Account storage ac = st.a[who];
        require(ac.inited, "no-entries");
        require(entryIndex != 0 && entryIndex < ac.entries.length, "bad-index");

        roll(st, who, nowTs);

        Entry storage e = ac.entries[entryIndex];
        require(e.amount >= amount, "bad-amount");
        e.amount -= amount;

        if (e.inSpendable) {
            require(ac.spendableTotal >= uint256(amount), "spendable-underflow");
            ac.spendableTotal -= uint256(amount);
        } else {
            uint64 bKey = _bucketKey(e.unlockTime);
            Bucket storage bk = ac.locked[bKey];
            if (bk.total >= amount) {
                bk.total -= amount;
            } else {
                bk.total = 0;
            }
            if (ac.lockedTotal >= uint256(amount)) {
                ac.lockedTotal -= uint256(amount);
            } else {
                ac.lockedTotal = 0;
            }
        }
    }

    function reduceUnlockTime(State storage st, address who, uint256 entryIndex, uint64 newUnlockTime, uint64 nowTs)
        internal
    {
        Account storage ac = st.a[who];
        require(ac.inited, "no-entries");
        require(entryIndex != 0 && entryIndex < ac.entries.length, "bad-index");

        roll(st, who, nowTs);

        Entry storage e = ac.entries[entryIndex];
        require(!e.inSpendable, "already-spendable");
        require(e.amount != 0, "empty-entry");
        require(newUnlockTime < e.unlockTime, "not-reduction");
        require(newUnlockTime >= e.minUnlockTime, "below-min");

        uint64 oldB = _bucketKey(e.unlockTime);
        uint64 newB = _bucketKey(newUnlockTime);
        if (oldB == newB) {
            e.unlockTime = newUnlockTime;
            return;
        }

        // decrement old bucket total
        Bucket storage oldBk = ac.locked[oldB];
        if (oldBk.total >= e.amount) oldBk.total -= e.amount;
        else oldBk.total = 0;

        // unlink from old bucket entry-chain (scan)
        uint32 prev = 0;
        uint32 cur = oldBk.headEntry;
        while (cur != 0 && cur != uint32(entryIndex)) {
            prev = cur;
            cur = ac.entries[cur].nextInBucket;
        }
        if (cur == 0) {
            // if missing, just update unlockTime and reinsert
            e.unlockTime = newUnlockTime;
        } else {
            uint32 nxt = ac.entries[cur].nextInBucket;
            if (prev == 0) {
                oldBk.headEntry = nxt;
            } else {
                ac.entries[prev].nextInBucket = nxt;
            }
            if (oldBk.tailEntry == uint32(entryIndex)) {
                oldBk.tailEntry = prev;
            }
            ac.entries[cur].nextInBucket = 0;
            e.unlockTime = newUnlockTime;
        }

        // insert into new bucket (append)
        Bucket storage nb = ac.locked[newB];
        if (nb.headEntry == 0) {
            _insertBucketSorted(ac, newB);
            nb.headEntry = uint32(entryIndex);
            nb.tailEntry = uint32(entryIndex);
        } else {
            ac.entries[nb.tailEntry].nextInBucket = uint32(entryIndex);
            nb.tailEntry = uint32(entryIndex);
        }
        nb.total += e.amount;
        // lockedTotal unchanged (amount stayed locked)
    }

    // -------------------------
    // Entry access (per sweep/revoke/reduce)
    // -------------------------
    function entryCount(State storage st, address who) internal view returns (uint256) {
        Account storage ac = st.a[who];
        if (!ac.inited) return 0;
        // exclude dummy
        return ac.entries.length - 1;
    }

    function getEntry(State storage st, address who, uint256 entryIndex) internal view returns (Entry memory) {
        Account storage ac = st.a[who];
        require(ac.inited, "no-entries");
        require(entryIndex != 0 && entryIndex < ac.entries.length, "bad-index");
        return ac.entries[entryIndex];
    }

    // Minimal helper: mark entry as fully removed (used by sweep/revoke)
    function zeroEntry(State storage st, address who, uint256 entryIndex) internal {
        Account storage ac = st.a[who];
        require(ac.inited, "no-entries");
        require(entryIndex != 0 && entryIndex < ac.entries.length, "bad-index");
        ac.entries[entryIndex].amount = 0;
        // next pointers left as-is (safe); queue advancement happens on spend/roll
    }
}
