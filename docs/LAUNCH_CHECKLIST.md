# Grow a Brainrot: Launch Checklist

Do these in order. Tick each box when it's done.

## 1. Save the game
- [ ] In Studio, go to **File → Save As** and save over `GrowABrainrot.rbxl` (or `GrowACreature.rbxlx`). Do this first. Studio is still running an auto-recovery copy.

## 2. Check the name
- [ ] On roblox.com, search **"Grow a Brainrot"**. If a popular game already uses that exact name, pick a twist, such as *Brainrot Mixing Lab* or *Grow a Brainrot: Potion Lab*.
- [ ] Don't use another game's logo, characters or exact name in your title, icon or thumbnails.

## 3. Publish
- [ ] **File → Publish to Roblox As…** and create a new experience. Leave it **Private** for now.
- [ ] **Game Settings → Security**: turn on **Enable Studio Access to API Services**. Saving won't work without it.
- [ ] Still in Security: leave **Allow HTTP Requests** off. The game doesn't need it.
- [ ] **Game Settings → Basic Info**: set the genre (Simulator), the description, and the devices (Computer, Phone, Tablet).

## 4. Make the Robux items (on create.roblox.com → your experience → Monetization)
Make each item, then paste its ID into **ReplicatedStorage → ShopConfig**, replacing `id = 0`.
Each time you press Play, Studio's Output lists every item that still says 0.

Game passes (bought once):
- [ ] VIP: 399 R$
- [ ] 2x Cash: 499 R$
- [ ] Lucky Brewer, Fast Brew, Big Lab (prices are in ShopConfig)

Developer products (can be bought again):
- [ ] Cash 1 / 2 / 3, Cash Boost, Luck Boost, Speed Boost, Instant Hatch, Satchel Refill, Market Restock, Legendary Crate, Mythic Box
- [ ] Growth Potion: 39 R$
- [ ] Legendary Wings: 149 R$
- [ ] Name Tags x3: 29 R$

Use the **same Robux price** on the website as in ShopConfig, so the in-game button shows the right number.

## 5. Icon and thumbnails
- [ ] Icon: upload `game_icon_512.png` (512×512).
- [ ] Thumbnails (1920×1080): press Play in Studio, build a few creatures, give one wings and grow it, then take full-screen screenshots of your yard. The new 3D creatures on their pedestals look great. Add 2–3 thumbnails.

## 6. Test with real players (the game must be published)
- [ ] **Saving**: play, build a creature, leave, and rejoin. The creature should still be there.
- [ ] **Trading**: in Studio go to **Test → Clients and Servers**, choose 2 players, then Start. Trade a creature from one player to the other. Check the creature moves and nobody loses anything.
- [ ] **Phone**: in Studio go to **Test → Device**, pick a phone, and press Play. Check you can tap every button.
- [ ] **One real purchase**: after the IDs are pasted, buy the cheapest item (Name Tags, 29 R$) once in the live game to check that you receive it.

## 7. Go live
- [ ] Set the experience to **Public**.
- [ ] Fill in the **Experience Questionnaire** (content maturity). The game has cartoon battles only, so it should get a low rating.
- [ ] Share it with friends first and watch them play. Wherever they get confused is what to fix next.

---

### Already done and checked in Studio
- New-player path: starting cash is enough, and the first 3 creatures are guaranteed a head and torso.
- Buy → brew → open capsule → build → collect cash works end to end.
- All 8 creature families have 3D parts, Wings, Growth, naming, and the Robux items.
- No hidden scripts in any free model. All 31 scripts belong to this game.
- Buttons are bigger on phones.
