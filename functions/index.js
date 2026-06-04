const {getMessaging} = require("firebase-admin/messaging");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

const ALL_USERS_TOPIC = "allUsers";

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

    const listingTitle = readText(listing.title, "New product listing");
    const price = readText(listing.priceLabel, "");
    const location = readText(listing.location, "");
    const marketplaceUrl = readText(listing.marketplaceUrl, "");
    const body = [listingTitle, price, location].filter(Boolean).join(" - ") ||
      "Tap to view the latest marketplace item.";

    await getMessaging().send({
      topic: ALL_USERS_TOPIC,
      notification: {
        title: "New listing added",
        body,
      },
      data: {
        type: "new_listing",
        title: "New listing added",
        body,
        listingId: event.params.listingId,
        marketplaceUrl,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "marketplace_listing_alerts",
          sound: "default",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
          priority: "high",
          defaultSound: true,
        },
      },
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    });

    logger.info("Sent new marketplace listing notification.", {
      listingId: event.params.listingId,
      topic: ALL_USERS_TOPIC,
    });
  },
);

function readText(value, fallback) {
  if (value === undefined || value === null) return fallback;
  const text = String(value).trim();
  return text || fallback;
}
