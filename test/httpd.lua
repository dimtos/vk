require "socket"
local pkg = { t0 = os.clock() }

local server = require('http.server').new( app.config.httpd.host, app.config.httpd.port )

local output =
{
	['200'] = function(req, res)
		return req:render{ json = res }
	end,

	['400'] = function(req)
		local resp = req:render{ json = { error = 'Incorrect JSON' } }
		resp.status = 400
		return resp
	end,

	['404'] = function(req)
		local resp = req:render{ json = { error = 'Key not found' } }
		resp.status = 404
		return resp
	end,

	['409'] = function(req)
		local resp = req:render{ json = { error = 'Key already exists' } }
		resp.status = 409
		return resp
	end,

	['429'] = function(req)
		local resp = req:render{ json = { error = 'Request limit exceeded' } }
		resp.status = 429
		return resp
	end,
}



--box.space.test:on_replace(function(old, new, space, op)
--	local msg = op:upper() ..' in `'.. space ..'`: '.. (new.key or old.key)
--	log.info(msg)
--end)



server:hook( 'before_dispatch', function(self, req)
	log.info(pkg.t0)
	log.info(os.clock())
	local now = os.clock()
	log.info( now - pkg.t0 )
	pkg.t0 = os.clock()
end)



server:route( { path = '/kv/*key', method = 'GET' },
	function(req)
		local k = req:stash('key')
		local found = box.space.test:select{k}[1] -- это у нас primary_index
		return
			found
			and output['200']( req, found:tomap{names_only = true} )
			or output['404'](req)
	end
)

server:route( { path = '/kv/*key', method = 'DELETE' },
	function(req)
		local k = req:stash('key')
		local found = box.space.test:delete{k}
		return
			found
			and output['200']( req, {ok = true} )
			or output['404'](req)
	end
)

server:route( { path = '/kv/*key', method = 'PUT' },
	function(req)
		local k = req:stash('key')
		local ok, body, resp = pcall( req.json, req )
		if not ok or body.value == nil then
			return output['400'](req)
		end

		local found = box.space.test:update( {k}, {{ '=', 'value', body.value }} )
		return
			found
			and output['200']( req, found:tomap{names_only = true} )
			or output['404'](req)
	end
)

server:route( { path = '/kv/*key', method = 'POST' },
	function(req)
		local ok, body, resp = pcall( req.json, req )
		if not ok or body.key == nil or body.value == nil then
			return output['400'](req)
		end

		local space = box.space.test
		local ok, found = pcall( space.insert, space, { body.key, body.value } )
		return ok -- опять же именно в нашем случае единственным случаем, когда не разместится тапл, является дубль ключа, так как остальные проверки проведены ранее
			and output['200']( req, found:tomap{names_only = true} )
			or output['409'](req)
	end
)

server:start()

return pkg
