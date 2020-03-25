# OTRS-Teams
Microsoft Teams integration for OTRS

Provides an event based module to send a notification to a Microsoft Teams webhook. A webhook per Teams channel is needed. The webhook URL is choosen based on the queue it was associated with. This association is done in System Config item TeamsNotification::QueueToWebhookURL.

Follow the below link on how to create a webhook:
https://docs.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook

Example:
![alt text](https://i.ibb.co/7S2f2Nk/MSTeams-OTRS-Notification.png "OTRS-Teams-Notification")
