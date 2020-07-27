# README

This app receives webhooks from Shopify (product updates, collection updates, etc.) and queues them up for processing in the Resque redis DB belonging to the main incartupsell app *if* a job for the same object is not already in the queue.

It's in a separate app because we sometimes get a gazillion product updates all at once, and it's a giant pain if that makes the main app fall over.
