import com.Components.RightClickItem;
import com.GameInterface.Chat;
import com.GameInterface.InventoryItem;
import com.GameInterface.Tradepost;
import com.Utils.Text;
import mx.utils.Delegate;
import com.Utils.Archive;
import com.Utils.ID32;
import com.Components.InventoryItemList.MCLItemInventoryItem;

import com.GameInterface.Inventory;
import com.GameInterface.Game.Character;

class TradepostUtil
{    
	private var m_swfRoot: MovieClip;
	
	static var ARCHIVE_NAMES:String = "PriceHistoryName";
	static var ARCHIVE_VALUES:String = "PriceHistoryValue";
	
	var m_tradepostInventory:Inventory;
	
	var m_PromptSaleOriginal:Function;
	var m_UpdateRightClickMenuOriginal:Function;
	
	var m_priceHistory:Array;
	
	public static function main(swfRoot:MovieClip):Void 
	{
		var tradepostUtil = new TradepostUtil(swfRoot);
		
		swfRoot.onLoad = function() { tradepostUtil.OnLoad(); };
		swfRoot.OnUnload =  function() { tradepostUtil.OnUnload(); };
		swfRoot.OnModuleActivated = function(config:Archive) { tradepostUtil.Activate(config); };
		swfRoot.OnModuleDeactivated = function() { return tradepostUtil.Deactivate(); };
	}
	
    public function TradepostUtil(swfRoot: MovieClip) 
    {
		m_swfRoot = swfRoot;
    }
	
	public function OnLoad()
	{
		m_tradepostInventory = new Inventory(new com.Utils.ID32(_global.Enums.InvType.e_Type_GC_TradepostContainer, Character.GetClientCharID().GetInstance()));
		
		setTimeout(Delegate.create(this, WireupMethods), 200);
	}
	
	function WireupMethods()
	{
		var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
		
		m_PromptSaleOriginal = Delegate.create(buyView, buyView.PromptSale);
		buyView.PromptSale = Delegate.create(this, PromptSaleOverride);
		
		m_UpdateRightClickMenuOriginal = Delegate.create(buyView, buyView.UpdateRightClickMenu);
		buyView.UpdateRightClickMenu = Delegate.create(this, UpdateRightClickMenuOverride);
		
		buyView.m_SellItemPromptWindow.SignalPromptResponse.Disconnect(buyView.SlotSellPromptResponse, buyView);
		buyView.m_SellItemPromptWindow.SignalPromptResponse.Connect(SlotSellPromptResponse, this);
	}
	
	function SlotSellPromptResponse(price:Number)
	{
		var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
		
		var currentInventory:Inventory = new Inventory(buyView.m_SellItemInventory);
		var item:InventoryItem = currentInventory.GetItemAt(buyView.m_SellItemSlot);
		m_priceHistory[item.m_Name] = price;
		
		buyView.SlotSellPromptResponse(price);
	}
	
	function UpdateRightClickMenuOverride(RightClickMode:Number, item:MCLItemInventoryItem, itemSlot:Number)
	{
		m_UpdateRightClickMenuOriginal(RightClickMode, item, itemSlot);
		
		var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
		
		if (RightClickMode == 1) //Right Click Sale
		{
			var newProvider:Array = new Array();
			var dataProvider:Array = buyView.m_RightClickMenu.dataProvider;
			
			newProvider.push(dataProvider.shift());
			
			var inventoryItem:InventoryItem = m_tradepostInventory.GetItemAt(itemSlot);
			var originalPrice = m_priceHistory[inventoryItem.m_Name];
			if (originalPrice)
			{
				var option:RightClickItem = new RightClickItem("Price: " + Text.AddThousandsSeparator(originalPrice), true, RightClickItem.CENTER_ALIGN);
				option.SignalItemClicked.Connect(SearchOptionClickEventHandler, this);
				newProvider.push(option);
			}
			
			while (dataProvider.length > 0)
			{
				newProvider.push(dataProvider.shift());
			}
			
			var option:RightClickItem = new RightClickItem("Price Check", false, RightClickItem.LEFT_ALIGN);
			option.SignalItemClicked.Connect(SearchOptionClickEventHandler, this);
			newProvider.push(option);
			
			buyView.m_RightClickMenu.dataProvider = newProvider;
		}
	}
	
	function SearchOptionClickEventHandler()
	{
		var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
		
		var item = m_tradepostInventory.GetItemAt(buyView.m_CancelSaleSlot);
		
		SearchForItem(item);
	}
	
	function PromptSaleOverride(inventoryID:ID32, slotID:Number)
	{
		m_PromptSaleOriginal(inventoryID, slotID);
		
		var currentInventory:Inventory = new Inventory(inventoryID);
		var item:InventoryItem = currentInventory.GetItemAt(slotID);
		
		SearchForItem(item);
	}
	
	function SearchForItem(item:InventoryItem)
	{
		var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
		
		buyView.m_SearchField.text = item.m_Name;
		var itemType = FindItemType(item);
		SetDropdownSelection(buyView.m_ItemTypeDropdownMenu, itemType, "idx");
		buyView.m_UseExactNameCheckBox.selected = true;
		
		buyView.Search();
	}
	
	function FindItemType(item:InventoryItem) 
	{
		for (var type in Tradepost.m_TradepostItemTypes)
		{
			for (var i in Tradepost.m_TradepostItemTypes[type])
			{
				var subtype = Tradepost.m_TradepostItemTypes[type][i];
				if (item.m_ItemTypeGUI == subtype)
				{
					
					return type;
				}
			}
		}
	}
	
	function SetDropdownSelection(dropdown, targetItem, matchingProperty) 
	{
		for (var i in dropdown._dataProvider)
		{
			var item = dropdown._dataProvider[i];
			if (item[matchingProperty] == targetItem)
			{
				dropdown.selectedIndex = i;
			}
		}
	}
	
	public function Activate(config: Archive)
	{
		var names:Array = config.FindEntryArray(ARCHIVE_NAMES);
		var prices:Array = config.FindEntryArray(ARCHIVE_VALUES);
		m_priceHistory = new Array();
		if (names && prices && names.length == prices.length)
		{
			for (var i = 0; i < names.length; i++ )
			{
				m_priceHistory[names[i]] = prices[i];
			}
		}
	}
	
	public function Deactivate(): Archive
	{
		var archive: Archive = new Archive();
		for (var i in m_priceHistory)
		{
			archive.AddEntry(ARCHIVE_NAMES, i);
			archive.AddEntry(ARCHIVE_VALUES, m_priceHistory[i]);
		}
		return archive;
	}
}