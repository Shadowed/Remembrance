if( GetLocale() ~= "deDE" ) then
	return;
end

RemembranceLocals = setmetatable( {
}, { __index = RemembranceLocals } );