/**
 * Store-receipt validation behind one interface. Selection happens in index.ts
 * (like store selection): DevFakeValidator in dev without store credentials;
 * the Google/Apple implementations activate when env creds exist.
 */

export interface ValidatedPurchase {
  orderId: string;
  productId: string;
}

export interface PurchaseValidator {
  /** Returns the canonical order for a Google Play purchase token, or null if invalid. */
  validateGoogle(purchaseToken: string, productId: string): Promise<ValidatedPurchase | null>;
  /** Returns the canonical order for an App Store receipt, or null if invalid. */
  validateApple(receipt: string): Promise<ValidatedPurchase | null>;
}

/**
 * Dev/test validator: accepts tokens/receipts of the exact form
 * `fake:{orderId}:{productId}` and nothing else. Used by all tests.
 */
export class DevFakeValidator implements PurchaseValidator {
  private parse(raw: string): ValidatedPurchase | null {
    const m = /^fake:([^:]+):([^:]+)$/.exec(raw);
    return m ? { orderId: m[1]!, productId: m[2]! } : null;
  }

  async validateGoogle(purchaseToken: string, productId: string): Promise<ValidatedPurchase | null> {
    const parsed = this.parse(purchaseToken);
    return parsed && parsed.productId === productId ? parsed : null;
  }

  async validateApple(receipt: string): Promise<ValidatedPurchase | null> {
    return this.parse(receipt);
  }
}

/**
 * Google Play Developer API validator — env-gated stub. Activated when
 * GOOGLE_SA_JSON is set; the real purchases.products.get call lands with the
 * store-release milestone (needs a service account + published app).
 */
export class GooglePlayValidator implements PurchaseValidator {
  constructor(private serviceAccountJson: string) {}

  async validateGoogle(_purchaseToken: string, _productId: string): Promise<ValidatedPurchase | null> {
    // TODO(release): androidpublisher purchases.products.get with this.serviceAccountJson.
    throw new Error('GooglePlayValidator not implemented — remove GOOGLE_SA_JSON to use DevFakeValidator in dev');
  }

  async validateApple(_receipt: string): Promise<ValidatedPurchase | null> {
    return null; // wrong platform
  }
}

/**
 * App Store verifyReceipt validator — env-gated stub. Activated when
 * APPLE_SHARED_SECRET is set; the real verifyReceipt/App Store Server API call
 * lands with the store-release milestone.
 */
export class AppleValidator implements PurchaseValidator {
  constructor(private sharedSecret: string) {}

  async validateGoogle(_purchaseToken: string, _productId: string): Promise<ValidatedPurchase | null> {
    return null; // wrong platform
  }

  async validateApple(_receipt: string): Promise<ValidatedPurchase | null> {
    // TODO(release): App Store Server API with this.sharedSecret.
    throw new Error('AppleValidator not implemented — remove APPLE_SHARED_SECRET to use DevFakeValidator in dev');
  }
}

/** Composite: routes each platform to its configured validator. */
export class PlatformValidators implements PurchaseValidator {
  constructor(private google: PurchaseValidator, private apple: PurchaseValidator) {}

  validateGoogle(purchaseToken: string, productId: string): Promise<ValidatedPurchase | null> {
    return this.google.validateGoogle(purchaseToken, productId);
  }

  validateApple(receipt: string): Promise<ValidatedPurchase | null> {
    return this.apple.validateApple(receipt);
  }
}
