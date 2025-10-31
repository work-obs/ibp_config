echo Do not run this file it will not work you MUST source this file
 # op://Private/openrouter_key/password
export AWS_ACCESS_KEY_ID=$(op read op://Private/NetstockAWS/username)
export AWS_SECRET_ACCESS_KEY=$(op read op://Private/NetstockAWS/password)
