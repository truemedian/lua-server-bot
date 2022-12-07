
local fs = require('fs')

return {
	prefix = '&',
	token = assert(fs.readFileSync('.token')):trim(),

	discordia = {
		logFile = 'logs/discordia.log',
		routeDelay = 100,
	}
}
