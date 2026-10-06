class_name CampaignCurrencyText
extends RefCounted

static func format_amount(value: float) -> String:
	return "$%d" % int(value)
