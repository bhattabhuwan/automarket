const {getMessaging} = require("firebase-admin/messaging");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

const NEW_DEVICE_TOPIC = "marketplace-new-devices";

exports.notifyNewMarketplaceDevice = onDocumentCreated(
  "listings/{listingId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.warn("New listing trigger fired without a snapshot.", {
        listingId: event.params.listingId,
      });
      return;
    }

    const listing = snapshot.data() || {};
    if (listing.isActive === false) {
      logger.info("Skipping inactive listing notification.", {
        listingId: event.params.listingId,
      });
      return;
    }

    const listingTitle = readText(listing.title, "New marketplace device");
    const price = readText(listing.priceLabel, "");
    const location = readText(listing.location, "");
    const body = [listingTitle, price, location].filter(Boolean).join(" • ") ||
      "Tap to view the latest marketplace device.";

    await getMessaging().send({
      topic: NEW_DEVICE_TOPIC,
      notification: {
        title: "New device uploaded",
        body,
      },
      data: {
        type: "new_marketplace_device",
        listingId: event.params.listingId,
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });

    logger.info("Sent new marketplace device notification.", {
      listingId: event.params.listingId,
      topic: NEW_DEVICE_TOPIC,
    });
  },
);

function readText(value, fallback) {
  if (value === undefined || value === null) return fallback;
  const text = String(value).trim();
  return text || fallback;
}
