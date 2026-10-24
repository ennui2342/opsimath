# The Finds queue (docs/BARGAIN_HUNTING.md): eBay listings on covers Mark
# wants that are under his target price or well below their cover's
# usual price. Phone-first — Discord notifications will link here.
class FindsController < ApplicationController
  def index
    @finds = Finds.all
  end
end
