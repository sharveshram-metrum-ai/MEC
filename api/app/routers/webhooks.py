"""
Webhook handlers for external services.

This is the main reason we need FastAPI alongside PostgREST:
- Stripe webhooks require signature verification
- Auth0 webhooks need external API calls
- Both require business logic that can't be in SQL
"""

import logging
from typing import Optional

from fastapi import APIRouter, Request, HTTPException, Header
import httpx

from app.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()


# =============================================================================
# STRIPE WEBHOOKS
# =============================================================================

@router.post("/stripe")
async def stripe_webhook(
    request: Request,
    stripe_signature: Optional[str] = Header(None, alias="Stripe-Signature")
):
    """
    Handle Stripe webhook events.
    
    Events handled:
    - customer.subscription.created → Provision plan entitlements
    - customer.subscription.updated → Update entitlements
    - customer.subscription.deleted → Revoke entitlements
    - invoice.paid → Log payment
    - invoice.payment_failed → Alert
    """
    if not settings.STRIPE_WEBHOOK_SECRET:
        logger.warning("Stripe webhook secret not configured")
        raise HTTPException(status_code=500, detail="Webhook not configured")
    
    payload = await request.body()
    
    try:
        import stripe
        event = stripe.Webhook.construct_event(
            payload,
            stripe_signature,
            settings.STRIPE_WEBHOOK_SECRET
        )
    except ValueError as e:
        logger.error(f"Invalid Stripe payload: {e}")
        raise HTTPException(status_code=400, detail="Invalid payload")
    except stripe.error.SignatureVerificationError as e:
        logger.error(f"Invalid Stripe signature: {e}")
        raise HTTPException(status_code=400, detail="Invalid signature")
    
    event_type = event["type"]
    data = event["data"]["object"]
    
    logger.info(f"Received Stripe event: {event_type}")
    
    # Handle subscription events
    if event_type == "customer.subscription.created":
        await handle_subscription_created(data)
    elif event_type == "customer.subscription.updated":
        await handle_subscription_updated(data)
    elif event_type == "customer.subscription.deleted":
        await handle_subscription_deleted(data)
    elif event_type == "invoice.paid":
        await handle_invoice_paid(data)
    elif event_type == "invoice.payment_failed":
        await handle_invoice_failed(data)
    else:
        logger.info(f"Unhandled Stripe event type: {event_type}")
    
    return {"status": "received", "event_type": event_type}


async def handle_subscription_created(subscription: dict):
    """Provision entitlements for new subscription."""
    customer_id = subscription.get("customer")
    price_id = subscription.get("items", {}).get("data", [{}])[0].get("price", {}).get("id")
    
    logger.info(f"New subscription: customer={customer_id}, price={price_id}")
    
    # TODO: Map price_id to plan_id
    # TODO: Find or create account by customer_id (external_id)
    # TODO: Call PostgREST to provision entitlements
    # 
    # async with httpx.AsyncClient() as client:
    #     response = await client.post(
    #         f"{settings.POSTGREST_URL}/rpc/provision_plan",
    #         json={"p_account_id": account_id, "p_plan_id": plan_id},
    #         headers={"Authorization": f"Bearer {service_jwt}"}
    #     )


async def handle_subscription_updated(subscription: dict):
    """Update entitlements for changed subscription."""
    customer_id = subscription.get("customer")
    status = subscription.get("status")
    
    logger.info(f"Subscription updated: customer={customer_id}, status={status}")
    
    # TODO: Handle plan changes, pauses, etc.


async def handle_subscription_deleted(subscription: dict):
    """Revoke entitlements for cancelled subscription."""
    customer_id = subscription.get("customer")
    
    logger.info(f"Subscription deleted: customer={customer_id}")
    
    # TODO: Expire/revoke entitlements for this customer


async def handle_invoice_paid(invoice: dict):
    """Log successful payment."""
    customer_id = invoice.get("customer")
    amount = invoice.get("amount_paid", 0) / 100  # Convert from cents
    
    logger.info(f"Invoice paid: customer={customer_id}, amount=${amount}")
    
    # TODO: Log payment event if needed


async def handle_invoice_failed(invoice: dict):
    """Handle failed payment."""
    customer_id = invoice.get("customer")
    
    logger.warning(f"Invoice payment failed: customer={customer_id}")
    
    # TODO: Send alert, update account status, etc.


# =============================================================================
# AUTH0 WEBHOOKS
# =============================================================================

@router.post("/auth0")
async def auth0_webhook(request: Request):
    """
    Handle Auth0 webhook events.
    
    Events handled:
    - User created → Create MEC account
    - User updated → Sync account details
    - User deleted → Deactivate account
    """
    payload = await request.json()
    
    # TODO: Verify Auth0 webhook signature
    
    event_type = payload.get("type")
    user = payload.get("user", {})
    
    logger.info(f"Received Auth0 event: {event_type}")
    
    if event_type == "user.created":
        await handle_user_created(user)
    elif event_type == "user.updated":
        await handle_user_updated(user)
    elif event_type == "user.deleted":
        await handle_user_deleted(user)
    else:
        logger.info(f"Unhandled Auth0 event type: {event_type}")
    
    return {"status": "received", "event_type": event_type}


async def handle_user_created(user: dict):
    """Create MEC account for new Auth0 user."""
    user_id = user.get("user_id")
    email = user.get("email")
    name = user.get("name") or email
    
    logger.info(f"Creating account for user: {user_id}")
    
    # TODO: Create account in MEC via PostgREST
    # 
    # async with httpx.AsyncClient() as client:
    #     response = await client.post(
    #         f"{settings.POSTGREST_URL}/accounts",
    #         json={
    #             "external_id": user_id,
    #             "display_name": name,
    #             "email": email,
    #             "account_type_code": "user",
    #         },
    #         headers={"Authorization": f"Bearer {service_jwt}"}
    #     )


async def handle_user_updated(user: dict):
    """Sync Auth0 user changes to MEC account."""
    user_id = user.get("user_id")
    
    logger.info(f"Updating account for user: {user_id}")
    
    # TODO: Update account in MEC


async def handle_user_deleted(user: dict):
    """Deactivate MEC account for deleted Auth0 user."""
    user_id = user.get("user_id")
    
    logger.info(f"Deactivating account for user: {user_id}")
    
    # TODO: Set account status to 'inactive'


# =============================================================================
# GENERIC WEBHOOK
# =============================================================================

@router.post("/generic")
async def generic_webhook(request: Request):
    """Generic webhook endpoint for testing or custom integrations."""
    payload = await request.json()
    
    logger.info(f"Received generic webhook: {payload}")
    
    return {"status": "received", "payload": payload}
