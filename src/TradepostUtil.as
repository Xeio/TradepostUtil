import com.Components.RightClickItem;
import com.Components.RightClickMenu;
import com.GameInterface.DistributedValue;
import com.GameInterface.DressingRoom;
import com.GameInterface.DressingRoomNode;
import com.GameInterface.InventoryItem;
import com.GameInterface.Tradepost;
import com.GameInterface.MailData;
import com.GameInterface.ShopInterface;
import com.GameInterface.ScryWidgets;
import com.Utils.LDBFormat;
import flash.geom.Point;
import mx.utils.Delegate;
import com.Utils.Archive;
import com.Utils.ID32;
import xeio.TradepostUtils;
import com.GameInterface.Log;
import com.GameInterface.LogBase;

import com.GameInterface.Game.CharacterBase;
import com.GameInterface.Inventory;
import com.GameInterface.GroupFinder;
import com.GameInterface.Playfield;
import com.GameInterface.Game.Character;
import com.GameInterface.Game.BuffData;
import com.GameInterface.Spell;

class TradepostUtil
{    
	private var m_swfRoot: MovieClip;
	
	private var m_openButton: MovieClip
	private var m_sellButton: MovieClip
	
	private var m_Inventory:Inventory;
	private var m_OpenShop:ShopInterface;
	private var m_openBagsCommand:DistributedValue;
	private var m_sellItemsCommand:DistributedValue;
	private var m_OpenBagsValue:String;
	private var m_itemSellCount:Number = 0;
	private var m_itemsToSell:Array = [];
	private var m_itemsToOpen:Array = [];
	
	
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
		setTimeout(Delegate.create(this, AutoSearch), 200);
	}
	
	var m_PromptSaleOriginal:Function;
	function AutoSearch()
	{
		var buyView = _root.tradepost.m_Window.m_Content.m_ViewsContainer.m_BuyView;
		m_PromptSaleOriginal = Delegate.create(buyView, buyView.PromptSale);
		buyView.PromptSale = Delegate.create(this, PromptSaleOverride);
	}
	
	function PromptSaleOverride(inventoryID:ID32, slotID:Number)
	{
		m_PromptSaleOriginal(inventoryID, slotID);
		
		var currentInventory:Inventory = new Inventory(inventoryID);
		var item:InventoryItem = currentInventory.GetItemAt(slotID);
		
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
}