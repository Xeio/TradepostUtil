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
	static var ARCHIVE_EXPIRATIONS:String = "PriceHistoryExpiration";
	static var HOUR:Number = 60 * 60;
	static var DAY:Number = HOUR * 24;
	static var EXPIRE_TIMEOUT:Number = DAY * 3; // 3 days
	
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
		var priceRecord = GetOrAddRecord(item.m_Name);
		priceRecord.price = price;
		priceRecord.expire = GetNewExpireTime();
		
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
			var priceRecord = GetOrAddRecord(inventoryItem.m_Name);
			
			if (priceRecord.price > 0)
			{
				var option:RightClickItem = new RightClickItem("Price: " + Text.AddThousandsSeparator(priceRecord.price), true, RightClickItem.CENTER_ALIGN);
				newProvider.push(option);
			}
			
			if (priceRecord.expire > 0)
			{
				var timeTillExpire:Number = priceRecord.expire - (new Date()).getUTCSeconds();
				var message:String;
				if (timeTillExpire < 0)
				{
					message = "EXPIRED";
				}
				else if (timeTillExpire >= DAY)
				{
					message = "Expires in " + Math.round(timeTillExpire/DAY) + " day(s)";
				}
				else if (timeTillExpire >= HOUR)
				{
					message = "Expires in " + Math.round(timeTillExpire/HOUR) + " hour(s)";
				}
				else
				{
					message = "Expires soon";
				}		
				var option:RightClickItem = new RightClickItem(message, true, RightClickItem.CENTER_ALIGN);
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
	
	function GetNewExpireTime():Number
	{
		return (new Date()).getUTCSeconds() + EXPIRE_TIMEOUT;
	}
	
	function GetOrAddRecord(itemName:String):Object
	{
		for (var i = 0; i < m_priceHistory.length; i++ )
		{
			if (m_priceHistory[i].name == itemName)
			{
				return m_priceHistory[i];
			}
		}
		var newItem = new Object();
		newItem.name = itemName;
		newItem.price = 0;
		newItem.expire = 0;
		m_priceHistory.push(newItem);
		return newItem;
	}
	
	public function Activate(config: Archive)
	{
		var names:Array = config.FindEntryArray(ARCHIVE_NAMES);
		var prices:Array = config.FindEntryArray(ARCHIVE_VALUES);
		var expirations:Array = config.FindEntryArray(ARCHIVE_EXPIRATIONS);
		m_priceHistory = new Array();
		if (names && prices && names.length == prices.length)
		{
			for (var i = 0; i < names.length; i++ )
			{
				m_priceHistory[i] = new Object();
				m_priceHistory[i].name = names[i];
				m_priceHistory[i].price = prices[i];
				m_priceHistory[i].expire = expirations[i] || 0;
			}
		}
	}
	
	public function Deactivate(): Archive
	{
		var archive: Archive = new Archive();
		for (var i = 0; i < m_priceHistory.length; i++ )
		{
			archive.AddEntry(ARCHIVE_NAMES,  m_priceHistory[i].name);
			archive.AddEntry(ARCHIVE_VALUES, m_priceHistory[i].price);
			archive.AddEntry(ARCHIVE_EXPIRATIONS, m_priceHistory[i].expire);
		}
		return archive;
	}
}