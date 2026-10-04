# Spoolman + Bambu operating guide

## What is automated

The P2S and X2D publish printer and AMS state to Home Assistant through the
Bambu Lab integration. The X2D uses direct local MQTT. SpoolmanSync reads those
entities and monitors:

- P2S: four AMS trays and one external spool position
- X2D: four AMS trays and two external spool positions

After a print, Home Assistant sends an authenticated webhook to SpoolmanSync.
SpoolmanSync deducts the measured filament use from the Spoolman spool assigned
to the active tray. Bambu Studio or OrcaSlicer only needs to select the correct
AMS slot when slicing/printing.

## One-time inventory onboarding

Spoolman currently has no spool records. A physical spool must exist in
Spoolman before it can be assigned to an AMS tray.

For each physical spool:

1. Open `https://spoolman.jerrettdavis.com/` and choose **Add spools**.
2. Record the manufacturer, material, color, nominal filament weight, empty
   spool weight, and measured remaining weight. Use a scale when the spool has
   already been opened.
3. Save the spool.
4. In Home Assistant, open **SpoolmanSync > Dashboard**, select the matching
   printer/tray, and choose the new spool.

Do not create one generic record per color and reuse it for multiple physical
spools. Every physical spool needs its own Spoolman record so remaining weight
and history stay accurate.

## Easiest day-to-day workflow

### Bambu RFID spools

Assign a new Bambu spool once in SpoolmanSync. SpoolmanSync remembers the
spool's AMS RFID serial. On later unload/reload cycles it can match that same
physical spool automatically, including when it moves to another tray.

### Third-party spools

1. On an Android phone connected to Tailscale or the home network, open
   `https://spools.jerrettdavis.com/scan` in Chrome.
2. Under **Write NFC Tag**, select the physical spool record.
3. Choose **Write**, then hold a blank NFC sticker against the phone's NFC
   antenna until Chrome reports success.
4. Put the sticker on the physical spool as described below.
5. When loading the spool, unlock the phone and tap the sticker. The stable
   assignment page opens; select the P2S or X2D and the exact AMS/external
   position.

This is the dependable fallback because generic AMS metadata normally reports
material and color, but not a unique physical-spool identifier.

The tag contains an NDEF URL pointing at the spool's assignment page. It does
not contain a password, Tailscale credential, Home Assistant token, or
Spoolman API credential.

### Where to attach an NFC sticker

- Use one tag per physical spool, not one tag per filament color or product.
- Put it flat on the outside face of a spool flange, between the hub and the
  outer rim. About 25–50 mm from the hub is a useful target.
- Keep it away from the outer circumference and flange edge where AMS rollers
  and guides contact the spool.
- Do not fold the antenna over an edge. Avoid metal or foil-backed surfaces;
  use an on-metal NFC tag if the spool itself is metal.
- Mark the location with an NFC symbol or small label so it is easy to find
  with the phone.
- The sticker does not need to line up with a Bambu RFID reader. It is read by
  the Android phone before or while loading the spool.

If a cardboard flange is damaged or replaced, write a new sticker from the
same spool record and discard the old tag. Do not create a second Spoolman
spool merely because its tag was replaced.

### Android NFC requirements

- Use Chrome on Android with NFC enabled.
- The phone must be on the home network or connected to the tailnet and using
  the home DNS resolver.
- Use the HTTPS URL above. Web NFC will not operate from the direct
  `http://10.0.0.160:3000` address.
- Chrome may request NFC permission the first time. Grant it only for the
  private `spools.jerrettdavis.com` site.
- If a tap opens the URL but cannot load it, verify Tailscale and DNS before
  rewriting the sticker; the NDEF data is probably still correct.

### Printing from Bambu Studio or OrcaSlicer

1. Synchronize/refresh the printer's AMS filaments in the slicer.
2. Map each project filament to the actual AMS tray you intend to use.
3. Send the print normally.

There is no additional Spoolman action at print time. The slicer controls the
tray choice; Home Assistant and SpoolmanSync perform the usage deduction after
the print completes.

## Loading and swapping checklist

- Bambu RFID spool previously assigned: load it and allow automatic matching.
- New Bambu RFID spool: create its Spoolman record and assign it once.
- Third-party spool: create its Spoolman record, label it, then scan/tap and
  select the tray.
- External spool: assign it to the explicitly named external position. The X2D
  has two separate external positions.
- Before a long print, confirm the SpoolmanSync dashboard shows the intended
  spool in every tray the job may use.

## Current service locations

- Spoolman: `https://spoolman.jerrettdavis.com/`
- SpoolmanSync: Home Assistant sidebar, **SpoolmanSync**
- NFC/QR assignment UI: `https://spools.jerrettdavis.com/`
- Private machine endpoint: `https://spoolman-ha.jerrettdavis.com:8444`

The machine endpoint is restricted to the Home Assistant hosts and is not an
interactive user URL. The NFC/QR endpoint is restricted at Traefik to the home
LANs (`10.0.0.0/24`, `10.0.107.0/24`) and Tailscale (`100.64.0.0/10`). Internal
DNS resolves it to `10.0.0.120`; public DNS returns NXDOMAIN, so it is not a
public service.

The NFC/QR base URL is configured in **SpoolmanSync > Settings > QR Code / NFC
URL**. Its saved value must remain `https://spools.jerrettdavis.com`.

## Verification and troubleshooting

After a completed print:

1. Open **SpoolmanSync > Logs** and confirm a usage event was attributed to the
   expected printer, tray, and spool.
2. Open the spool in Spoolman and verify its remaining weight decreased.
3. If no usage was deducted, check **SpoolmanSync > Automations**. It should say
   **Automations Configured** and list both P2S and X2D.
4. If a tray shows no spool, assign or scan the physical spool before the next
   print. Do not guess between visually identical spools; weigh or identify the
   physical spool first.
5. If **Write NFC Tag** says no spools were found, create the physical spool in
   Spoolman first. The NFC writer does not invent inventory records.
6. If Android does not offer NFC writing, confirm Chrome, NFC enabled, HTTPS,
   and access to `spools.jerrettdavis.com` through LAN or Tailscale.

## Re-deploying the NFC endpoint

The repository includes an idempotent publisher and a contract test:

```powershell
& .\scripts\spoolman\tests\Test-SpoolmanSyncNfcEndpoint.ps1
scp -o HostKeyAlias=jdh-docker-00 .\scripts\spoolman\publish-spoolmansync-nfc-endpoint.sh jd@10.0.0.120:/home/jd/
ssh -o HostKeyAlias=jdh-docker-00 jd@10.0.0.120 'chmod 700 /home/jd/publish-spoolmansync-nfc-endpoint.sh && /home/jd/publish-spoolmansync-nfc-endpoint.sh'
```

The publisher adds the Traefik file-provider router, private source allowlist,
Cloudflare DNS-01 certificate resolver, and backend to
`http://10.0.0.160:3000`. It preserves the existing Portainer and AdGuard
routes and makes a timestamped `rules.yaml.pre-spoolmansync-nfc.*` backup.

The AdGuard rewrite `spools.jerrettdavis.com -> 10.0.0.120` and the saved
SpoolmanSync NFC base URL are stateful settings. The future homelab repository
should manage and verify both declaratively.

## Adding printers or changing entities

When another printer is added, the Bambu integration is upgraded in a way that
renames entities, or SpoolmanSync is upgraded with an automation regeneration
notice:

1. Confirm the printer appears on the SpoolmanSync dashboard.
2. Open **SpoolmanSync > Automations**.
3. Choose **Reconfigure Automations**.
4. Perform the requested full Home Assistant restart.
5. Verify all printers and tray counts on the Automations page.
